import AppKit
import IOKit.ps

/// The duck noticing what goes on around it and having feelings about it: which app you switch to, how often
/// you switch, coming back to your Mac, dark mode, the battery, copy-paste marathons and long focused stretches.
/// Only counts and names are used; nothing you copy or type is ever read.
@MainActor
final class Reactions {
    private let duck: Duck
    private let talk: Talk
    private var prefs: Prefs { Settings.shared.prefs }
    private var feelings: Feelings { .shared }
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    private var switches: [Date] = []
    private var lastSaid = Date()
    private var appCooldown: [String: Date] = [:]
    private var greeted: String?
    private var focusApp: String?
    private var focusSince = Date()
    private var praisedFocus = Date.distantPast
    private var copies: [Date] = []
    private var lastCopyCount = NSPasteboard.general.changeCount
    private var copyQuipped = Date.distantPast
    private var wasCharging: Bool?
    private var warnedBattery = false

    init(duck: Duck, talk: Talk) {
        self.duck = duck
        self.talk = talk
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.switched(to: app) }
        })
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cameBack() }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cameBack() }
        })
        observers.append(distributed.addObserver(forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                self?.say(dark ? .darkMode : .lightMode, chance: 1)
            }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // Say hello for the time of day shortly after starting.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            self?.greet()
        }
    }

    // MARK: Things happening

    private func switched(to app: NSRunningApplication?) {
        guard let app, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
        let now = Date()
        switches = switches.filter { now.timeIntervalSince($0) < 30 } + [now]
        if switches.count >= 8 {
            switches.removeAll()
            say(.appHopping, chance: 1)
            return
        }
        if focusApp != id {
            focusApp = id
            focusSince = now
        }
        guard (appCooldown[id] ?? .distantPast) < now else { return }
        let odds: Int = switch prefs.chattiness {
        case .quiet: 0
        case .normal: 4
        case .chaos: 2
        }
        guard odds > 0, Int.random(in: 0..<odds) == 0, now.timeIntervalSince(lastSaid) > 45,
              let line = Lines.about(app: app.localizedName ?? id, bundleID: id, prefs.personality) else { return }
        appCooldown[id] = now.addingTimeInterval(20 * 60)
        speak(line)
    }

    private func cameBack() {
        feelings.feel(.userCameBack)
        if !greet() { say(.welcomeBack, chance: 2) }
    }

    /// Good morning, happy Friday and so on, once per part of the day. Returns whether it said anything.
    @discardableResult
    private func greet() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)  // 1 is Sunday
        let part: Moment = switch hour {
        case 5..<12: weekday == 2 ? .monday : (weekday == 6 ? .friday : .morning)
        case 12..<17: .afternoon
        case 17..<23: (weekday == 1 || weekday == 7) ? .weekend : .evening
        default: .lateNight
        }
        let key = "\(calendar.ordinality(of: .day, in: .era, for: now) ?? 0)-\(part.rawValue)"
        guard greeted != key else { return false }
        greeted = key
        return say(part, chance: 1)
    }

    private func check() {
        let now = Date()
        // Copy-paste marathons, counted, never read.
        let count = NSPasteboard.general.changeCount
        if count != lastCopyCount {
            copies = copies.filter { now.timeIntervalSince($0) < 60 } + Array(repeating: now, count: min(5, count - lastCopyCount))
            lastCopyCount = count
            if copies.count >= 6, now.timeIntervalSince(copyQuipped) > 30 * 60 {
                copyQuipped = now
                say(.copyPaste, chance: 1)
            }
        }
        // A long stretch in one app (that isn't a distraction) while you're active is worth a little praise.
        if Desk.idleSeconds < 60, now.timeIntervalSince(focusSince) > 45 * 60, now.timeIntervalSince(praisedFocus) > 60 * 60 {
            praisedFocus = now
            feelings.feel(.keptGoal)
            say(.longFocus, chance: 1)
        }
        if Int(now.timeIntervalSinceReferenceDate) % 120 < 3 { checkBattery() }
    }

    private func checkBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              let capacity = description[kIOPSCurrentCapacityKey] as? Int else { return }
        let charging = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        if let was = wasCharging, !was, charging { say(.charging, chance: 2) }
        wasCharging = charging
        if !charging, capacity <= 15, !warnedBattery {
            warnedBattery = true
            say(.batteryLow, fill: ["percent": "\(capacity)"], chance: 1)
        }
        if charging || capacity > 20 { warnedBattery = false }
    }

    // MARK: Saying it

    @discardableResult
    private func say(_ moment: Moment, fill: [String: String] = [:], chance: Int) -> Bool {
        guard Int.random(in: 0..<max(1, chance)) == 0 else { return false }
        return speak(Lines.pick(moment, prefs.personality, fill: fill.merging(["user": prefs.userName]) { $1 }))
    }

    @discardableResult
    private func speak(_ line: String) -> Bool {
        guard !prefs.paused, !prefs.hidden, !talk.isOpen, duck.bubble == nil, !duck.isBusy, duck.activity != .sleeping else { return false }
        lastSaid = Date()
        duck.say(line)
        return true
    }
}
