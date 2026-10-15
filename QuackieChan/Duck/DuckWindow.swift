import AppKit
import SwiftUI

/// A panel that can take typing (for the talk box) without making Quackie Chan the active app.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The duck's two see-through panels above every window (the duck, and its speech bubble) and everything the
/// duck does on its own: waddling, flying up onto your windows and hopping between them, falling off when you
/// move one, getting thrown and bouncing off the screen edges, typing along with you, dancing to your music,
/// napping when you're away, and acting on how it feels.
@MainActor
final class DuckWindow {
    let duck = Duck()
    let talk = Talk()
    var actions = DuckActions()
    /// Something happened the duck has feelings about.
    var onEvent: ((Feelings.Event) -> Void)?

    private let panel: NSPanel
    private let bubblePanel: KeyPanel
    private let placement = BubblePlacement()
    private var ticker: Timer?
    private var feelings: Feelings { .shared }
    private var prefs: Prefs { Settings.shared.prefs }

    /// Where the duck's feet are, in screen coordinates.
    private var feet = CGPoint.zero
    private var velocity = CGVector.zero
    private var airborne = false
    /// Flying on purpose (lighter, flapping) rather than falling.
    private var soaring = false
    private var perch: Desk.Window?
    private var walkTarget: CGFloat?
    private var nextAntic = Date().addingTimeInterval(12)
    private var tickCount = 0
    private var stageSize = DuckStage.size(pixel: 3)

    private var dragOffset = CGVector.zero
    private var dragSamples: [(time: TimeInterval, point: CGPoint)] = []
    private var dragging = false

    private var lastKeyCount = Desk.keyPresses
    private var keysPerSecond = 0.0
    private var typingSince: Date?
    private var quietSince: Date?
    private var franticQuipped = Date.distantPast

    private var song: Music.Song?
    private var musicSince: Date?
    private var wentBananas = false
    private var danceAnchor: CGFloat?
    /// Runs once the duck lands from its next jump.
    private var onLand: (() -> Void)?
    /// Where the next jump comes down, when it isn't onto the floor or a window's top.
    private var landingY: CGFloat?

    private var pokes: [Date] = []
    private var hoverSince: Date?
    private var dareUntil: Date?
    private var lastMouse = CGPoint.zero
    private var lastStartle = Date.distantPast

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: stageSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bubblePanel = KeyPanel(contentRect: NSRect(origin: .zero, size: BubbleStage.size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        for window in [panel, bubblePanel] as [NSPanel] {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.ignoresMouseEvents = true
        }
        bubblePanel.becomesKeyOnlyIfNeeded = true
        talk.onListening = { [weak self] listening in
            guard let self else { return }
            if listening { self.duck.set(.listening) } else if self.duck.activity == .listening { self.duck.set(.idle) }
        }
    }

    func show() {
        var wired = actions
        wired.poke = { [weak self] in self?.poked() }
        wired.dragChanged = { [weak self] in self?.dragChanged() }
        wired.dragEnded = { [weak self] in self?.dragEnded() }
        wired.hover = { [weak self] inside in self?.hoverSince = inside ? Date() : nil }
        panel.contentView = NSHostingView(rootView: DuckStage(duck: duck, actions: wired))
        bubblePanel.contentView = NSHostingView(rootView: BubbleStage(duck: duck, talk: talk, placement: placement))
        if feet == .zero, let screen = NSScreen.main {
            feet = CGPoint(x: screen.visibleFrame.maxX - stageSize.width / 2 - 40, y: screen.visibleFrame.maxY - 40)
            airborne = true  // drops in from the top
        }
        place()
        panel.orderFrontRegardless()
        bubblePanel.orderFrontRegardless()
        startTicking(fast: true)
    }

    /// 60 frames a second while anything moves, so flying and dancing are smooth; 20 when it's standing still,
    /// so an idle duck costs next to nothing.
    private var fast = true
    private var lastTick = ProcessInfo.processInfo.systemUptime

    private func startTicking(fast: Bool) {
        self.fast = fast
        ticker?.invalidate()
        let timer = Timer(timeInterval: fast ? 1.0 / 60 : 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                self.tick(min(0.1, now - self.lastTick))
                self.lastTick = now
            }
        }
        timer.tolerance = fast ? 0.002 : 0.01
        RunLoop.main.add(timer, forMode: .common)  // keeps going while menus are open
        ticker = timer
    }

    private var isMoving: Bool {
        airborne || dragging || walkTarget != nil || duck.isDancing || duck.isInMotion
            || [.typing, .celebrating, .pecking, .dizzy].contains(duck.activity)
    }

    func hide() {
        panel.orderOut(nil)
        bubblePanel.orderOut(nil)
        ticker?.invalidate()
        ticker = nil
    }

    var isVisible: Bool { panel.isVisible }

    /// Opens the talk box and, if asked, starts listening.
    func openTalk(listening: Bool) {
        if !isVisible { show() }
        talk.open(listening: listening)
        bubblePanel.ignoresMouseEvents = false
        bubblePanel.makeKeyAndOrderFront(nil)
    }

    // MARK: The loop

    private var clocks: [String: TimeInterval] = [:]

    /// True once every `seconds`, whatever the frame rate.
    private func every(_ seconds: TimeInterval, _ name: String) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - (clocks[name] ?? 0) >= seconds else { return false }
        clocks[name] = now
        return true
    }

    private func tick(_ dt: TimeInterval) {
        tickCount += 1
        if isMoving != fast { startTicking(fast: isMoving) }
        duck.mood = feelings.mood
        duck.step(by: dt)
        let mouse = NSEvent.mouseLocation
        duck.mouse = CGPoint(x: mouse.x - feet.x, y: mouse.y - (feet.y + 40 * pixel))
        if every(0.1, "clicks") { updatePassThrough(mouse) }
        if every(0.5, "notice") { noticeTyping(); noticeAway(); noticeMouse(mouse) }
        if every(1, "feel") { feelings.drift(by: 1); resizeIfNeeded() }
        if every(4, "music"), ProcessInfo.processInfo.environment["QUACKIE_DEMO"] != "bananas" { noticeMusic() }
        if let since = hoverSince, Date().timeIntervalSince(since) > 1.2, !dragging, duck.isFree, duck.activity != .petted {
            duck.set(.petted)
            feelings.feel(.petted)
            if Int.random(in: 0..<3) == 0 { say(.pet) }
        }
        if hoverSince == nil, duck.activity == .petted { duck.set(.idle) }
        if let dare = dareUntil, Date() > dare {
            dareUntil = nil
            duck.set(.idle)
            duck.say("That's what I thought.")
        }

        guard !dragging else { return }
        if airborne {
            fly(dt)
        } else {
            ride()
            walk(dt)
            dance()
            antics()
        }
        place()
    }

    private var pixel: CGFloat { prefs.size.pixel }
    private var spriteHeight: CGFloat { CGFloat(DuckArt.canvasHeight) * pixel }

    private func resizeIfNeeded() {
        let size = DuckStage.size(pixel: pixel)
        guard size != stageSize else { return }
        stageSize = size
        panel.setContentSize(size)
    }

    /// Puts the duck where its feet are (two art pixels above the canvas bottom), and its bubble over its head,
    /// or under it when there's no room above.
    private func place() {
        let origin = NSPoint(x: (feet.x - stageSize.width / 2).rounded(), y: (feet.y - 2 * pixel).rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }

        let visible = screen.visibleFrame
        let head = feet.y + spriteHeight * 0.78
        let size = BubbleStage.size
        let below = head + size.height > visible.maxY
        var x = feet.x - size.width / 2
        x = min(max(x, visible.minX), visible.maxX - size.width)
        let y = below ? feet.y + spriteHeight * 0.15 - size.height : head
        let bubbleOrigin = NSPoint(x: x.rounded(), y: max(visible.minY, y).rounded())
        if bubblePanel.frame.origin != bubbleOrigin { bubblePanel.setFrameOrigin(bubbleOrigin) }
        let shift = ((feet.x + (duck.facingLeft ? -8 : 8) * pixel) - (x + size.width / 2)).rounded()
        if placement.below != below { placement.below = below }
        if placement.tailShift != shift { placement.tailShift = shift }
    }

    private var screen: NSScreen {
        NSScreen.screens.first { $0.frame.contains(feet) } ?? panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: Flying, falling, landing

    private func fly(_ dt: TimeInterval) {
        let previous = feet
        velocity.dy -= (soaring ? 900 : 2400) * dt
        feet.x += velocity.dx * dt
        feet.y += velocity.dy * dt

        // Bounce off the sides and the top of the screen. The bubble moves out of the way, so it can go all the way up.
        let bounds = screen.visibleFrame
        let half = CGFloat(DuckArt.canvasWidth) * pixel / 2
        if feet.x < bounds.minX + half || feet.x > bounds.maxX - half {
            feet.x = min(max(feet.x, bounds.minX + half), bounds.maxX - half)
            velocity.dx *= -0.6
            if abs(velocity.dx) > 400 { duck.spawn(.sparkle); Sounds.shared.play(.thud) }
        }
        let ceiling = bounds.maxY - spriteHeight * 0.85
        if feet.y > ceiling {
            feet.y = ceiling
            velocity.dy = -abs(velocity.dy) * 0.4
        }

        guard velocity.dy < 0 else { return }
        if let target = landingY {
            if feet.y <= target { land(on: target, perch: windowUnder(x: feet.x, top: target)) }
            return
        }
        // Land on the first window top it falls past that isn't hidden behind another window, else the floor.
        if let window = windowCrossed(from: previous.y, to: feet.y, x: feet.x) {
            land(on: window.frame.maxY, perch: window)
        } else if feet.y <= bounds.minY {
            land(on: bounds.minY, perch: nil)
        }
    }

    /// The front-most window whose top edge lies between two heights at `x`, with that bit of edge not covered.
    private func windowCrossed(from top: CGFloat, to bottom: CGFloat, x: CGFloat) -> Desk.Window? {
        let windows = Desk.windows()
        for (index, window) in windows.enumerated()
        where window.frame.maxY <= top && window.frame.maxY >= bottom
            && x > window.frame.minX + 20 && x < window.frame.maxX - 20
            && window.frame.maxY < screen.visibleFrame.maxY - spriteHeight * 0.8 {
            let edge = CGPoint(x: x, y: window.frame.maxY - 2)
            if !windows[..<index].contains(where: { $0.frame.contains(edge) }) { return window }
        }
        return nil
    }

    private func windowUnder(x: CGFloat, top: CGFloat) -> Desk.Window? {
        Desk.windows().first { abs($0.frame.maxY - top) < 3 && x > $0.frame.minX && x < $0.frame.maxX }
    }

    private func land(on y: CGFloat, perch window: Desk.Window?) {
        let impact = -velocity.dy
        let wasSoaring = soaring
        feet.y = y
        perch = window
        airborne = false
        soaring = false
        velocity = .zero
        landingY = nil
        if let onLand {
            self.onLand = nil
            duck.set(.idle)
            onLand()
        } else if impact > 1500 && !wasSoaring {
            duck.set(.dizzy)
            feelings.feel(.landedHard)
            Sounds.shared.play(.thud)
            say(.dizzy)
            after(2.2) { [weak self] in if self?.duck.activity == .dizzy { self?.duck.set(.idle) } }
        } else {
            duck.set(.idle)
            duck.hop()
            if window != nil, Int.random(in: 0..<4) == 0 { say(.perch) }
        }
    }

    /// Flies (flapping, on purpose) to a spot. The arc is worked out to land right on it.
    private func flyTo(_ target: CGPoint) {
        let distance = hypot(target.x - feet.x, target.y - feet.y)
        let time = min(1.6, max(0.6, distance / 650))
        soaring = true
        velocity = CGVector(dx: (target.x - feet.x) / time, dy: (target.y - feet.y + 0.5 * 900 * time * time) / time)
        airborne = true
        perch = nil
        walkTarget = nil
        danceAnchor = nil
        landingY = target.y
        duck.facingLeft = target.x < feet.x
        duck.set(.soaring)
        feelings.feel(.flew)
        Sounds.shared.play(.whoosh)
    }

    /// Stays on top of the window it's standing on, and falls off when it moves or goes away.
    private func ride() {
        guard every(0.1, "ride") else { return }
        guard let current = perch else {
            // Nothing underneath (say the window it flew to closed on the way): down it goes.
            if feet.y > screen.visibleFrame.minY + 1, !duck.isBusy { fallOff(say: nil, push: 0) }
            return
        }
        guard let window = Desk.window(current.id), feet.x > window.frame.minX, feet.x < window.frame.maxX else {
            fallOff(say: .windowGone, push: 0)
            return
        }
        let moved = CGVector(dx: window.frame.minX - current.frame.minX, dy: window.frame.maxY - current.frame.maxY)
        if abs(moved.dx) + abs(moved.dy) > 1.5 {
            // The window was pulled out from under it.
            feet.x += moved.dx
            fallOff(say: .windowYanked, push: moved.dx * 4)
            feelings.feel(.windowYanked)
        }
    }

    private func fallOff(say moment: Moment?, push: CGFloat) {
        perch = nil
        airborne = true
        soaring = false
        velocity = CGVector(dx: max(-500, min(500, push)), dy: 120)
        duck.set(.flying)
        if let moment, Int.random(in: 0..<3) > 0 { say(moment) }
    }

    // MARK: Walking, dancing and antics

    private func walk(_ dt: TimeInterval) {
        guard let target = walkTarget, duck.activity == .idle || duck.activity == .walking else {
            if duck.activity == .walking { duck.set(.idle) }
            return
        }
        let distance = target - feet.x
        if abs(distance) < 2 {
            walkTarget = nil
            duck.set(.idle)
            return
        }
        duck.facingLeft = distance < 0
        duck.set(.walking)
        feet.x += (distance < 0 ? -1 : 1) * min(abs(distance), 50 * dt)
    }

    /// While dancing, sways side to side on the beat; going bananas, it really moves.
    private func dance() {
        guard duck.isDancing else {
            danceAnchor = nil
            return
        }
        let anchor = danceAnchor ?? feet.x
        danceAnchor = anchor
        // On the same beat clock as the bounces: dancing sways over four beats, bananas over two.
        let beats = duck.beatPhase
        let sway: CGFloat = switch duck.activity {
        case .bananas: 34 * CGFloat(sin(.pi * beats / 2))
        case .dancing: 20 * CGFloat(sin(.pi * beats / 4))
        default: 3 * CGFloat(sin(.pi * beats / 4))
        }
        var x = anchor + sway
        if let perch { x = min(max(x, perch.frame.minX + 30), perch.frame.maxX - 30) }
        feet.x = x
    }

    /// Now and then, when it's not busy, the duck does something on its own, depending on how it feels.
    private func antics() {
        guard Date() > nextAntic else { return }
        nextAntic = Date().addingTimeInterval(.random(in: 10...32))
        guard prefs.wander, duck.isFree, duck.activity != .petted, duck.bubble == nil else { return }
        if duck.activity == .sulking { duck.set(.idle) }

        switch feelings.mood {
        case .grumpy where Bool.random():
            duck.facingLeft.toggle()
            duck.set(.sulking)
            if Int.random(in: 0..<3) == 0 { say(.sulk) }
            after(.random(in: 6...14)) { [weak self] in if self?.duck.activity == .sulking { self?.duck.set(.idle) } }
            return
        case .sleepy where Int.random(in: 0..<3) == 0:
            duck.yawn()
            if Bool.random() { say(.yawn) }
            return
        case .bored where Int.random(in: 0..<3) == 0:
            duck.yawn()
            return
        case .hyped where Bool.random():
            duck.set(.celebrating)
            duck.spawn(.sparkle)
            after(1.6) { [weak self] in if self?.duck.activity == .celebrating { self?.duck.set(.idle) } }
            return
        case .loving where Int.random(in: 0..<3) == 0:
            duck.spawn(.heart)
            return
        default: break
        }

        let roll = Int.random(in: 0..<100)
        if roll < 40, flyToAWindow() {
            if Int.random(in: 0..<4) == 0 { say(.takeOff) }
        } else if roll < 52, perch != nil {
            // Back down to the floor.
            flyTo(CGPoint(x: feet.x + (duck.facingLeft ? -140 : 140), y: screen.visibleFrame.minY))
        } else if roll < 80 {
            walkSomewhere()
        } else if roll < 90 {
            duck.set(.celebrating)
            duck.spawn(.note)
            after(1.4) { [weak self] in if self?.duck.activity == .celebrating { self?.duck.set(.idle) } }
        } else {
            duck.facingLeft.toggle()
            duck.quack()
            Sounds.shared.play(.quack)
        }
    }

    // MARK: Tricks you can ask for

    /// Dances (or goes bananas) for a while, whatever's playing.
    func dance(_ style: Duck.Activity, for seconds: TimeInterval) {
        walkTarget = nil
        duck.beat = 0.5
        duck.set(style)
        if style == .bananas { feelings.feel(.bananas) }
        after(seconds) { [weak self] in if self?.duck.activity == style { self?.duck.set(.idle) } }
    }

    /// Flies to the top of some window, or back down to the floor if there isn't one.
    func flyAround() {
        if !flyToAWindow() { flyTo(CGPoint(x: feet.x + (duck.facingLeft ? -200 : 200), y: screen.visibleFrame.minY)) }
    }

    func jump() {
        guard !airborne else { return }
        duck.set(.idle)
        soaring = false
        airborne = true
        velocity = CGVector(dx: duck.facingLeft ? -60 : 60, dy: 900)
        duck.set(.flying)
        Sounds.shared.play(.quack)
    }

    /// Comes over to where the mouse is: walks if it's along the floor, flies if it's up somewhere.
    func comeToMouse() {
        let mouse = NSEvent.mouseLocation
        if abs(mouse.y - feet.y) < 120, perch == nil {
            walkTarget = min(max(mouse.x, screen.visibleFrame.minX + 60), screen.visibleFrame.maxX - 60)
        } else {
            let floor = screen.visibleFrame.minY
            let target = Desk.windows().first { $0.frame.minX < mouse.x && mouse.x < $0.frame.maxX && $0.frame.maxY < mouse.y + 200
                && $0.frame.maxY < screen.visibleFrame.maxY - spriteHeight * 0.8 }
            flyTo(CGPoint(x: mouse.x, y: target?.frame.maxY ?? floor))
        }
    }

    /// Picks the top of a visible window and flies there. Returns false if there's nowhere good to go.
    @discardableResult
    private func flyToAWindow() -> Bool {
        let windows = Desk.windows()
        let visible = screen.visibleFrame
        var spots: [CGPoint] = []
        for (index, window) in windows.enumerated() where window.id != perch?.id {
            let top = window.frame.maxY
            guard top < visible.maxY - spriteHeight * 0.8, top > visible.minY + 60, window.frame.width > 260 else { continue }
            let x = CGFloat.random(in: (window.frame.minX + 80)...(window.frame.maxX - 80))
            let edge = CGPoint(x: x, y: top - 2)
            guard visible.contains(CGPoint(x: x, y: top)), !windows[..<index].contains(where: { $0.frame.contains(edge) }) else { continue }
            spots.append(CGPoint(x: x, y: top))
        }
        guard let spot = spots.randomElement() else { return false }
        flyTo(spot)
        return true
    }

    private func walkSomewhere() {
        let range: ClosedRange<CGFloat>
        if let window = perch {
            range = (window.frame.minX + 60)...max(window.frame.minX + 61, window.frame.maxX - 60)
        } else {
            let area = screen.visibleFrame.insetBy(dx: stageSize.width / 2, dy: 0)
            guard area.width > 0 else { return }
            range = area.minX...area.maxX
        }
        walkTarget = .random(in: range)
    }

    /// Jumps onto the window, pecks at it, runs `close`, and gloats. Without a window it pecks where it stands.
    func peck(_ window: Desk.Window?, then close: @escaping @MainActor () async -> Void) {
        walkTarget = nil
        let peckAndClose = { [weak self] in
            guard let self else { return }
            self.duck.set(.pecking)
            Sounds.shared.play(.pop)
            self.after(1.1) { [weak self] in
                await close()
                guard let self else { return }
                self.feelings.feel(.closedSomething)
                self.duck.set(.celebrating)
                self.after(1.8) { [weak self] in
                    guard let self else { return }
                    self.duck.set(.idle)
                    // The window it stood on may be gone now.
                    self.fallOff(say: .windowGone, push: 0)
                }
            }
        }
        guard let window else { return peckAndClose() }
        let top = min(window.frame.maxY, screen.visibleFrame.maxY - spriteHeight * 0.85)
        let x = min(max(window.frame.minX + 170, screen.visibleFrame.minX + 60), window.frame.maxX - 80)
        flyTo(CGPoint(x: x, y: top))
        onLand = peckAndClose
    }

    /// Flies over to the front window and stands on it, then does `work`.
    func visitFrontWindow(then work: @escaping @MainActor () -> Void) {
        guard let window = Desk.frontWindow(), window.frame.maxY < screen.visibleFrame.maxY - spriteHeight * 0.8 else {
            return work()
        }
        let x = min(max(feet.x, window.frame.minX + 80), window.frame.maxX - 80)
        flyTo(CGPoint(x: x, y: window.frame.maxY))
        onLand = work
    }

    // MARK: Noticing you

    /// Sits down with a tiny laptop when you type, and panics along when you type like a maniac.
    private func noticeTyping() {
        let count = Desk.keyPresses
        let pressed = Double(count &- lastKeyCount) * 2  // checked twice a second
        lastKeyCount = count
        keysPerSecond = keysPerSecond * 0.5 + pressed * 0.5
        let now = Date()
        // Typing into the talk box doesn't count.
        guard !talk.isOpen else { return }

        if keysPerSecond > 2.5 {
            quietSince = nil
            if typingSince == nil { typingSince = now }
        } else if keysPerSecond < 0.6 {
            typingSince = nil
            if quietSince == nil { quietSince = now }
        }

        if duck.activity == .typing {
            duck.frantic = keysPerSecond > 7
            if duck.frantic, now.timeIntervalSince(franticQuipped) > 600 {
                franticQuipped = now
                say(.typingFrantic)
            }
            if let quiet = quietSince, now.timeIntervalSince(quiet) > 2.5 {
                duck.frantic = false
                duck.set(.idle)
                feelings.feel(.typedALot)
                if Int.random(in: 0..<4) == 0 { say(.typingDone) }
            }
        } else if let since = typingSince, now.timeIntervalSince(since) > 2, duck.activity == .idle || duck.activity == .walking {
            walkTarget = nil
            duck.set(.typing)
        }
    }

    private func noticeAway() {
        let idle = Desk.idleSeconds
        let sleepAfter: TimeInterval = feelings.mood == .sleepy ? 60 : 180
        if idle > sleepAfter, duck.activity == .idle || duck.activity == .petted || duck.activity == .sulking {
            duck.set(.sleeping)
            feelings.feel(.userLeft)
        } else if idle < 2, duck.activity == .sleeping {
            duck.set(.idle)
            duck.hop()
            feelings.feel(.userCameBack)
            say(.wake)
        }
    }

    /// Startles when the mouse whooshes right past its head.
    private func noticeMouse(_ mouse: CGPoint) {
        defer { lastMouse = mouse }
        let speed = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) * 2  // points per second, roughly
        let head = CGPoint(x: feet.x, y: feet.y + spriteHeight * 0.6)
        let near = hypot(mouse.x - head.x, mouse.y - head.y) < 70
        guard near, speed > 2500, duck.isFree, Date().timeIntervalSince(lastStartle) > 20 else { return }
        lastStartle = Date()
        duck.spawn(.exclaim)
        duck.hop()
        Sounds.shared.play(.quack)
        if Bool.random() { say(.startled) }
    }

    /// Dances when Spotify or Music is playing: vibes first, dances after a bit, then goes bananas.
    private func noticeMusic() {
        guard prefs.dance else {
            if duck.isDancing { duck.set(.idle) }
            return
        }
        Task { [weak self] in
            let playing = await Music.nowPlaying()
            self?.hear(playing)
        }
    }

    /// Pretends a banger has been playing for a minute.
    func demoMusic() {
        duck.set(.idle)
        musicSince = Date().addingTimeInterval(-60)
        hear(Music.Song(title: "Sandstorm", artist: "Darude", bpm: 136))
    }

    func startDancing() {
        musicSince = Date().addingTimeInterval(-25)
        hear(song ?? Music.Song(title: "the song in my head", artist: "me", bpm: 120))
    }

    private func hear(_ playing: Music.Song?) {
        let now = Date()
        guard let playing else {
            if duck.isDancing {
                duck.set(.idle)
                feelings.feel(.musicStopped)
                if Int.random(in: 0..<3) == 0 { say(.musicStopped) }
            }
            song = nil
            musicSince = nil
            wentBananas = false
            return
        }
        if song?.title != playing.title, duck.bubble == nil, !duck.isBusy {
            say(.newSong, fill: ["song": playing.title, "artist": playing.artist])
        }
        song = playing
        if musicSince == nil { musicSince = now }
        duck.beat = 60 / (playing.bpm ?? 120)
        feelings.feel(.music)

        let canDance = duck.isDancing || duck.isFree
        guard canDance, !airborne, !dragging else { return }
        walkTarget = nil
        let listening = now.timeIntervalSince(musicSince ?? now)
        if listening > 50, prefs.goBananas {
            duck.set(.bananas)
            if !wentBananas {
                wentBananas = true
                feelings.feel(.bananas)
                say(.bananas)
            }
        } else if listening > 18 {
            duck.set(.dancing)
        } else {
            if duck.activity != .vibing, Int.random(in: 0..<3) == 0 { say(.vibing) }
            duck.set(.vibing)
        }
    }

    // MARK: Pokes and drags

    private func poked() {
        let now = Date()
        if dareUntil != nil {
            // You were warned.
            dareUntil = nil
            duck.bang()
            Sounds.shared.play(.gunshot)
            feelings.feel(.firedGun)
            duck.say(Lines.pick(.pokeBang, prefs.personality))
            after(1.4) { [weak self] in if self?.duck.activity == .aiming { self?.duck.set(.idle) } }
            return
        }
        if talk.isOpen { return }
        pokes = pokes.filter { now.timeIntervalSince($0) < 3 } + [now]
        Sounds.shared.play(.quack)
        duck.quack()
        feelings.feel(.poked)
        if duck.activity == .sleeping { duck.set(.idle); say(.wake); return }
        switch pokes.count {
        case 7...:
            pokes.removeAll()
            feelings.feel(.pokedTooMuch)
            duck.set(.aiming)
            Sounds.shared.play(.cock)
            duck.say(Lines.pick(.pokeDare, prefs.personality), alarm: true, hold: 4)
            dareUntil = now.addingTimeInterval(4)
        case 4:
            duck.spawn(.anger)
            say(.pokeRage)
        case 1 where Int.random(in: 0..<2) == 0:
            say(.poke)
        default:
            duck.spawn(.anger)
        }
    }

    private func dragChanged() {
        let mouse = NSEvent.mouseLocation
        if !dragging {
            dragging = true
            dragOffset = CGVector(dx: feet.x - mouse.x, dy: feet.y - mouse.y)
            dragSamples = []
            walkTarget = nil
            perch = nil
            airborne = false
            soaring = false
            landingY = nil
            onLand = nil
            hoverSince = nil
            duck.set(.dragged)
            feelings.feel(.grabbed)
            if Int.random(in: 0..<3) == 0 { say(.grabbed) }
        }
        feet = CGPoint(x: mouse.x + dragOffset.dx, y: mouse.y + dragOffset.dy)
        dragSamples.append((ProcessInfo.processInfo.systemUptime, mouse))
        if dragSamples.count > 6 { dragSamples.removeFirst() }
        place()
    }

    /// Lets go: with the mouse's speed, so you can throw it.
    private func dragEnded() {
        dragging = false
        if let first = dragSamples.first, let last = dragSamples.last, last.time > first.time {
            let dt = last.time - first.time
            velocity = CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
        } else {
            velocity = .zero
        }
        let speed = hypot(velocity.dx, velocity.dy)
        velocity.dx = max(-3000, min(3000, velocity.dx))
        velocity.dy = max(-3000, min(3000, velocity.dy))
        airborne = true
        duck.set(.flying)
        if speed > 1200 {
            feelings.feel(.thrown)
            say(.thrown)
        }
    }

    // MARK: Clicks

    /// The panels only take clicks over the duck and its bubble; everywhere else they go to the window behind.
    private func updatePassThrough(_ mouse: NSPoint) {
        guard !dragging else { return }
        let frame = panel.frame
        let local = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)  // top-left origin, like SwiftUI
        let overDuck = duckRect.contains(local)
        if panel.ignoresMouseEvents == overDuck { panel.ignoresMouseEvents = !overDuck }

        let bubbleFrame = bubblePanel.frame
        let inBubble = CGPoint(x: mouse.x - bubbleFrame.minX, y: bubbleFrame.maxY - mouse.y)
        let overBubble = (duck.bubble != nil || talk.isOpen) && placement.contentRect.insetBy(dx: -4, dy: -4).contains(inBubble)
        if bubblePanel.ignoresMouseEvents == overBubble { bubblePanel.ignoresMouseEvents = !overBubble }
    }

    /// The duck's body in its panel, top-left origin.
    private var duckRect: CGRect {
        let width = CGFloat(DuckArt.canvasWidth) * pixel, height = spriteHeight
        let sprite = CGRect(x: (stageSize.width - width) / 2, y: stageSize.height - height, width: width, height: height)
        return CGRect(x: sprite.minX + 4 * pixel, y: sprite.minY + 14 * pixel, width: 38 * pixel, height: 44 * pixel)
    }

    // MARK: Helpers

    private func say(_ moment: Moment, fill: [String: String] = [:]) {
        guard !duck.isBusy || [.thrown, .windowGone, .grabbed, .windowYanked, .takeOff].contains(moment), !talk.isOpen else { return }
        duck.say(Lines.pick(moment, prefs.personality, fill: fill.merging(["user": prefs.userName]) { $1 }))
    }

    private func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            await work()
        }
    }
}
