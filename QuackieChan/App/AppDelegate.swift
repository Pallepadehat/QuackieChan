import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let window = DuckWindow()
    private lazy var director = Director(window: window)
    private lazy var reactions = Reactions(duck: window.duck, talk: window.talk)
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.registerBundled()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.menuIcon()
        statusItem.button?.toolTip = settings.prefs.duckName
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        window.actions = DuckActions(
            talk: { [weak self] in self?.talk(listening: false) },
            tell: { [weak self] in self?.tell() },
            openSettings: { [weak self] in self?.openSettings() },
            togglePause: { [weak self] in self?.togglePause() },
            hide: { [weak self] in self?.toggleHidden() },
            quit: { NSApp.terminate(nil) })
        // The duck babbles along when it talks.
        window.duck.onSay = { [weak self] line in
            guard let self else { return }
            Sounds.shared.babble(line, personality: self.settings.prefs.personality)
        }
        if !settings.prefs.hidden { window.show() }
        director.start()
        reactions.start()

        // ⌃⌥Q: talk to the duck.
        HotKeys.shared.register(keyCode: kVK_ANSI_Q) { [weak self] in
            guard let self, self.settings.prefs.talkShortcut else { return }
            if self.window.talk.isOpen { self.window.talk.close() } else { self.talk(listening: true) }
        }

        // For tuning the brain: QUACKIE_ASK="what's your name?" prints the duck's answer and quits.
        if let question = ProcessInfo.processInfo.environment["QUACKIE_ASK"] {
            Task {
                let started = Date()
                let line: String
                if let known = Knowing.reply(to: question, settings: Settings.shared) {
                    line = "(knew it) " + known
                } else {
                    do {
                        let glance = await Eyes.lookNow()
                        print("(looked at \(glance?.appName ?? "nothing"), picture: \(glance?.image != nil), text: \(glance?.text?.count ?? 0) characters)")
                        fflush(stdout)
                        let answer = try await Minds.shared.answer(question, context: glance)
                        line = "\(answer?.say ?? "(no brain)") \(answer?.deeds ?? [])"
                    } catch {
                        line = "(error) \(error)"
                    }
                }
                print("[\(String(format: "%.1f", Date().timeIntervalSince(started)))s] \(line)")
                fflush(stdout)
                _exit(0)  // skips MLX's GPU teardown, which doesn't like being cut short
            }
            return
        }
        if let demo = ProcessInfo.processInfo.environment["QUACKIE_DEMO"] {
            Task { [director] in
                try? await Task.sleep(for: .seconds(3))
                await director.demo(demo)
            }
        } else if !settings.prefs.hasMet {
            settings.prefs.hasMet = true
            // After it has dropped in and landed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.director.greet()
                self?.openSettings()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.window.duck.quack()
                Sounds.shared.play(.quack)
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let prefs = settings.prefs
        let status = NSMenuItem(title: prefs.paused ? "\(prefs.duckName) is off duty" : "\(prefs.duckName) is watching 👀",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let talk = item("Talk to \(prefs.duckName)…", #selector(talkFromMenu), "q")
        talk.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(talk)
        menu.addItem(item("Tell \(prefs.duckName) a Goal…", #selector(tell), "t"))
        menu.addItem(item(prefs.paused ? "Start Watching" : "Pause Watching", #selector(togglePause), "p"))
        menu.addItem(item(prefs.hidden ? "Show Duck" : "Hide Duck", #selector(toggleHidden), "h"))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(item("Quit Quackie Chan", #selector(quit), "q"))
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func talkFromMenu() { talk(listening: false) }

    private func talk(listening: Bool) {
        if settings.prefs.hidden { toggleHidden() }
        window.openTalk(listening: listening)
    }

    @objc private func tell() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Tell \(settings.prefs.duckName) a goal"
        alert.informativeText = "Like \"I want to save money\", \"I'm trying to go to bed earlier\" or \"I'm learning Spanish\". "
            + "It switches on matching goals and remembers the rest for its AI brain."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "I want to save money"
        alert.accessoryView = field
        alert.addButton(withTitle: "Tell")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let added = settings.tell(field.stringValue)
        let line = Lines.pick(.noted, settings.prefs.personality)
        window.duck.say(added.isEmpty ? line : "\(added.map { "\($0.emoji) \($0.title)" }.joined(separator: ", ")). \(line)")
        window.duck.set(.celebrating)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.window.duck.activity == .celebrating { self?.window.duck.set(.idle) }
        }
    }

    @objc private func togglePause() {
        settings.prefs.paused.toggle()
        window.duck.say(settings.prefs.paused ? "Off duty. Do whatever. I'm not looking. 🙈" : "Back on duty. 👀")
    }

    @objc private func toggleHidden() {
        settings.prefs.hidden.toggle()
        if settings.prefs.hidden { window.hide() } else { window.show(); window.duck.quack() }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "Quackie Chan"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 820, height: 600))
            window.minSize = NSSize(width: 700, height: 480)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    /// A little duck for the menu bar, drawn from the same pixel art.
    private static func menuIcon() -> NSImage? {
        guard let image = DuckArt.image(skin: .standard, pose: Pose(), scale: 1),
              let cropped = image.cropping(to: CGRect(x: 3, y: 12, width: 44, height: 46)) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: 19, height: 20))
    }
}
