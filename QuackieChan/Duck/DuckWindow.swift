import AppKit
import SwiftUI

/// A see-through panel macOS doesn't push back under the menu bar, so the duck can stand on (or hang off) windows
/// right at the top of the screen with its head over the menu bar.
private class DuckPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// A panel that can take typing (for the talk box) without making Quackie Chan the active app.
private final class KeyPanel: DuckPanel {
    override var canBecomeKey: Bool { true }
}

/// Somewhere the duck can come down: the floor, or the top of a window. When a window's top is too close to the
/// top of the screen to stand on, it hangs off the edge by a wing instead.
private struct Spot {
    var x: CGFloat
    /// The floor, or the window's top edge.
    var top: CGFloat
    var window: Desk.Window?
    var hang = false
}

/// The duck's two see-through panels above every window (the duck, and its speech bubble) and everything the
/// duck does on its own: waddling, flying up onto your windows and hopping between them, falling off when you
/// move one, getting thrown and bouncing off the screen edges, typing along with you, dancing to your music,
/// napping when you're away, acting on how it feels, sitting when told to, and drinking when nobody pets it.
@MainActor
final class DuckWindow {
    let duck = Duck()
    let talk = Talk()
    var actions = DuckActions()
    /// What's left on the focus timer, like "🍅 12:34", or nil when it's off. For the menu bar.
    var onTimer: ((String?) -> Void)?
    /// Something happened the duck has feelings about.
    var onEvent: ((Feelings.Event) -> Void)?

    private let panel: NSPanel
    private let bubblePanel: KeyPanel
    private let placement = BubblePlacement()
    private var ticker: Timer?
    private var feelings: Feelings { .shared }
    private var booze: Booze { .shared }
    private var litter: Litter { .shared }
    private var droppings: Droppings { .shared }
    private var prefs: Prefs { Settings.shared.prefs }
    private var observers: [NSObjectProtocol] = []

    /// Where the duck's feet are, in screen coordinates.
    private var feet = CGPoint.zero
    private var velocity = CGVector.zero
    private var airborne = false
    /// Flying on purpose (lighter, flapping) rather than falling.
    private var soaring = false
    private var perch: Desk.Window?
    /// Holding on to the perch's top edge rather than standing on it.
    private var hanging: Bool {
        get { duck.hanging }
        set { duck.hanging = newValue }
    }
    /// The window it just fell or let go off, so it doesn't grab straight back on.
    private var letGo: CGWindowID?
    private var walkTarget: CGFloat?
    /// Walking backwards, smooth as anything.
    private var moonwalking = false
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
    /// Where the flight it's on comes down.
    private var landing: Spot?

    private var pokes: [Date] = []
    private var hoverSince: Date?
    private var dareUntil: Date?
    private var lastMouse = CGPoint.zero
    private var lastStartle = Date.distantPast
    private var lastDeskQuip = Date.distantPast
    private var lastDeskSwitch = Date.distantPast

    /// The cursor being blown across the screen by machine gun fire: from, to, and when it starts moving.
    private var shove: (from: CGPoint, to: CGPoint, start: TimeInterval)?
    private var lastBurst = Date.distantPast

    /// The focus timer: focusing or on a break, until when, and which round.
    private var tomato: (resting: Bool, until: Date, round: Int)?
    /// The stretch break: whether you said you'd join in, and the key count when it started.
    private var stretch: (joined: Bool, keys: UInt32)?
    /// The reverse Duck Hunt: where the crosshair is, how long it's been on the cursor, hits, and when it ends.
    private var hunt: (at: CGPoint, lockedOn: TimeInterval, hits: Int, lastShot: TimeInterval, starts: Date, ends: Date)?
    private lazy var crosshair = Crosshair()
    private var visitor: Visitor?
    private var lastVisit = Date()
    private var onACall = false

    /// On every desktop, or just the one it was started on.
    static var behavior: NSWindow.CollectionBehavior {
        Settings.shared.prefs.allDesktops ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            : [.stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    init() {
        panel = DuckPanel(contentRect: NSRect(origin: .zero, size: stageSize),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bubblePanel = KeyPanel(contentRect: NSRect(origin: .zero, size: BubbleStage.size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        for window in [panel, bubblePanel] as [NSPanel] {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            // Above the menu bar, so it can stand on windows right at the top of the screen.
            window.level = .statusBar
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.collectionBehavior = Self.behavior
            window.ignoresMouseEvents = true
        }
        bubblePanel.becomesKeyOnlyIfNeeded = true
        talk.onListening = { [weak self] listening in
            guard let self else { return }
            if listening { self.duck.set(.listening) } else if self.duck.activity == .listening { self.duck.set(.idle) }
        }
        duck.tipsy = booze.stage.rawValue
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.desktopChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
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
        litter.show()
        droppings.show()
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
        airborne || dragging || walkTarget != nil || duck.isDancing || duck.isInMotion || shove != nil || hunt != nil
            || [.typing, .celebrating, .pecking, .dizzy, .shooting, .eating, .stretching, .fighting, .partying, .pooping]
                .contains(duck.activity)
    }

    func hide() {
        panel.orderOut(nil)
        bubblePanel.orderOut(nil)
        litter.hide()
        droppings.hide()
        if hunt != nil { endHunt() }
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
        if shove != nil { blowCursorAway() }
        if every(0.1, "clicks") { updatePassThrough(mouse) }
        if every(0.5, "notice") { noticeTyping(); noticeAway(); noticeMouse(mouse) }
        if every(1, "feel") { feelings.drift(by: 1); resizeIfNeeded(); drinkIfThirsty(); tickTomato() }
        if every(2, "call") { noticeCall() }
        if hunt != nil { chase(mouse, dt) }
        if every(4, "music"), ProcessInfo.processInfo.environment["QUACKIE_DEMO"] != "bananas" { noticeMusic() }
        if let since = hoverSince, !dragging { beingPetted(for: Date().timeIntervalSince(since)) }
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
        let behavior = Self.behavior
        if panel.collectionBehavior != behavior {
            panel.collectionBehavior = behavior
            bubblePanel.collectionBehavior = behavior
            litter.layout()
        }
        let size = DuckStage.size(pixel: pixel)
        guard size != stageSize else { return }
        stageSize = size
        panel.setContentSize(size)
        litter.layout()
        // Hanging by the wing depends on its size.
        if hanging { fallOff(say: nil, push: 0) }
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

    /// True if some screen has this point on it.
    private func onAScreen(_ point: CGPoint) -> Bool {
        NSScreen.screens.contains { $0.frame.contains(point) }
    }

    /// The highest its feet go: its head may poke off the top of the screen a little, its body may not.
    private func ceiling(of screen: NSScreen) -> CGFloat {
        screen.frame.maxY - 20 * pixel
    }

    private func fly(_ dt: TimeInterval) {
        let previous = feet
        let home = screen
        velocity.dy -= (soaring ? 900 : 2400) * dt
        feet.x += velocity.dx * dt
        feet.y += velocity.dy * dt

        // Bounce off the sides and the top of the screen, unless another screen carries on past them.
        // The bubble moves out of the way, so it can go all the way up.
        let bounds = home.visibleFrame
        let half = CGFloat(DuckArt.canvasWidth) * pixel / 2
        let pastLeft = feet.x < bounds.minX + half && !onAScreen(CGPoint(x: home.frame.minX - 2, y: feet.y + 10))
        let pastRight = feet.x > bounds.maxX - half && !onAScreen(CGPoint(x: home.frame.maxX + 2, y: feet.y + 10))
        if pastLeft || pastRight {
            feet.x = min(max(feet.x, bounds.minX + half), bounds.maxX - half)
            velocity.dx *= -0.6
            if abs(velocity.dx) > 400 { duck.spawn(.sparkle); Sounds.shared.play(.thud) }
        }
        if feet.y > ceiling(of: home), !onAScreen(CGPoint(x: feet.x, y: home.frame.maxY + 2)) {
            feet.y = ceiling(of: home)
            velocity.dy = -abs(velocity.dy) * 0.4
        }

        guard velocity.dy < 0 else { return }
        if let target = landing {
            if feet.y <= feetY(target) { settle(target) }
            return
        }
        // Lands on (or grabs) the first window top it falls past that isn't hidden behind another window, else the
        // floor, unless there's another screen underneath to fall on to.
        if let spot = windowCrossed(from: previous.y, to: feet.y, x: feet.x) {
            settle(spot)
        } else if feet.y <= bounds.minY, !onAScreen(CGPoint(x: feet.x, y: home.frame.minY - 2)) {
            settle(Spot(x: feet.x, top: bounds.minY))
        }
    }

    /// Where its feet go for a spot: on top, or hanging below the edge.
    private func feetY(_ spot: Spot) -> CGFloat {
        spot.hang ? spot.top - CGFloat(DuckArt.hangDrop) * pixel : spot.top
    }

    /// Where on top of `window` it could go at `x`: standing, or hanging off the edge when there's no headroom.
    /// Nil for windows reaching up under the menu bar (full screen ones) and ones too low to bother with.
    private func spot(on window: Desk.Window, x: CGFloat) -> Spot? {
        let top = window.frame.maxY
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: x, y: top - 1)) }) else { return nil }
        let visible = screen.visibleFrame
        guard top <= visible.maxY + 2 else { return nil }
        let hang = top + CGFloat(DuckArt.standingHeight) * pixel > screen.frame.maxY
        let spot = Spot(x: x, top: top, window: window, hang: hang)
        guard feetY(spot) > visible.minY + 40 else { return nil }
        return spot
    }

    /// The front-most window whose top edge it passed between two heights at `x` (by its feet, or by its wing if
    /// it would hang off it), with that bit of edge not covered by another window.
    private func windowCrossed(from top: CGFloat, to bottom: CGFloat, x: CGFloat) -> Spot? {
        let windows = Desk.windows()
        for (index, window) in windows.enumerated()
        where window.id != letGo && x > window.frame.minX + 20 && x < window.frame.maxX - 20 {
            guard let spot = spot(on: window, x: x) else { continue }
            let grip = spot.top - feetY(spot)
            guard spot.top <= top + grip, spot.top >= bottom + grip else { continue }
            let edge = CGPoint(x: x, y: spot.top - 2)
            if !windows[..<index].contains(where: { $0.frame.contains(edge) }) { return spot }
        }
        return nil
    }

    private func settle(_ spot: Spot) {
        let impact = -velocity.dy
        let wasSoaring = soaring
        feet.y = feetY(spot)
        perch = spot.window
        hanging = spot.hang
        letGo = nil
        airborne = false
        soaring = false
        velocity = .zero
        landing = nil
        if let onLand {
            self.onLand = nil
            duck.set(.idle)
            onLand()
        } else if impact > 1500 && !wasSoaring && !spot.hang {
            duck.set(.dizzy)
            feelings.feel(.landedHard)
            Sounds.shared.play(.thud)
            say(.dizzy)
            after(2.2) { [weak self] in if self?.duck.activity == .dizzy { self?.duck.set(.idle) } }
        } else {
            duck.set(.idle)
            if spot.hang {
                if Int.random(in: 0..<3) == 0 { say(.hang) }
            } else {
                duck.hop()
                if spot.window != nil, Int.random(in: 0..<4) == 0 { say(.perch) }
            }
        }
    }

    /// Off whatever it was standing on or holding.
    private func leavePerch() {
        if let perch { letGo = perch.id }
        perch = nil
        hanging = false
    }

    /// Flies (flapping, on purpose) to a spot. The arc is worked out to land right on it, without bonking its head
    /// on the top of the screen on the way.
    private func flyTo(_ spot: Spot) {
        let target = CGPoint(x: spot.x, y: feetY(spot))
        let gravity: CGFloat = 900
        let distance = hypot(target.x - feet.x, target.y - feet.y)
        let rise = max(0, target.y - feet.y)
        // The quickest flight up there arrives at the top of its arc; anything slower goes higher first.
        let quickest = sqrt(2 * rise / gravity)
        var time = min(1.6, max(0.6, distance / 650))
        let top = ceiling(of: screen)
        for step in 0...8 {
            let candidate = time - (time - quickest) * CGFloat(step) / 8
            let up = (target.y - feet.y + 0.5 * gravity * candidate * candidate) / candidate
            if feet.y + max(0, up) * max(0, up) / (2 * gravity) <= top || step == 8 {
                time = max(0.3, candidate)
                break
            }
        }
        leavePerch()
        letGo = nil
        soaring = true
        velocity = CGVector(dx: (target.x - feet.x) / time, dy: (target.y - feet.y + 0.5 * gravity * time * time) / time)
        airborne = true
        walkTarget = nil
        danceAnchor = nil
        landing = spot
        duck.facingLeft = target.x < feet.x
        duck.set(.soaring)
        feelings.feel(.flew)
        Sounds.shared.play(.whoosh)
    }

    private func floor(at x: CGFloat) -> Spot {
        let visible = screen.visibleFrame
        return Spot(x: min(max(x, visible.minX + 60), visible.maxX - 60), top: visible.minY)
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
            fallOff(say: Desk.window(current.id) == nil && Date().timeIntervalSince(lastDeskSwitch) < 1.5 ? .newDesk : .windowGone, push: 0)
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
        leavePerch()
        landing = nil
        airborne = true
        soaring = false
        velocity = CGVector(dx: max(-500, min(500, push)), dy: 120)
        duck.set(.flying)
        if let moment, Int.random(in: 0..<3) > 0 { say(moment) }
    }

    // MARK: Walking, dancing and antics

    private func walk(_ dt: TimeInterval) {
        guard let target = walkTarget, [.idle, .walking, .hanging].contains(duck.activity) else {
            if duck.activity == .walking { duck.set(.idle) }
            moonwalking = false
            return
        }
        let distance = target - feet.x
        if abs(distance) < 2 {
            walkTarget = nil
            moonwalking = false
            duck.set(.idle)
            return
        }
        // Moonwalking faces the other way. Hanging, it shuffles along the edge wing over wing.
        duck.facingLeft = moonwalking ? distance > 0 : distance < 0
        if !hanging { duck.set(.walking) }
        // Drunk, it lurches: fast, slow, fast.
        let lurch = duck.tipsy >= 2 ? 0.4 + 1.2 * abs(sin(ProcessInfo.processInfo.systemUptime * 2.5)) : 1
        let speed: CGFloat = hanging ? 28 : (moonwalking ? 40 : 50)
        feet.x += (distance < 0 ? -1 : 1) * min(abs(distance), speed * lurch * dt)
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

        // Hanging off a window: shuffle along it a bit, or get tired and let go.
        if hanging {
            if Bool.random() {
                letGoOfTheEdge()
                if Int.random(in: 0..<2) == 0 { say(.letGo) }
            } else {
                walkSomewhere()
            }
            return
        }
        if duck.inMeeting { return }
        // A friend drops by now and then, while you're around.
        if prefs.visitors, perch == nil, !airborne, Date().timeIntervalSince(lastVisit) > 45 * 60,
           Desk.idleSeconds < 60, !duck.onTomato, !duck.staying, Int.random(in: 0..<12) == 0 {
            friendDropsBy()
            return
        }
        // Told to sit, or on the tomato, it stays put and fidgets.
        if duck.staying || duck.onTomato {
            switch Int.random(in: 0..<6) {
            case 0: duck.yawn()
            case 1: duck.spawn(.heart)
            case 2: duck.sneeze(); Sounds.shared.play(.pop)
            case 3: duck.quack(); Sounds.shared.play(.quack)
            default: duck.facingLeft.toggle()
            }
            return
        }

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
        if roll < 38, flyToAWindow() {
            if Int.random(in: 0..<4) == 0 { say(.takeOff) }
        } else if roll < 50, perch != nil {
            // Back down to the floor.
            flyTo(floor(at: feet.x + (duck.facingLeft ? -140 : 140)))
        } else if roll < 72 {
            walkSomewhere()
        } else if roll < 79, duck.tipsy < 3 {
            walkSomewhere()
            moonwalking = walkTarget != nil
            duck.spawn(.sparkle)
            if Int.random(in: 0..<3) == 0 { say(.moonwalk) }
        } else if roll < 84 {
            duck.sneeze()
            Sounds.shared.play(.pop)
            if Int.random(in: 0..<3) == 0 { after(1) { [weak self] in self?.say(.sneeze) } }
        } else if roll < 91 {
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
        standUp(saying: false)
        if hanging { letGoOfTheEdge() }
        walkTarget = nil
        duck.beat = 0.5
        duck.set(style)
        if style == .bananas { feelings.feel(.bananas) }
        after(seconds) { [weak self] in if self?.duck.activity == style { self?.duck.set(.idle) } }
    }

    /// Flies to the top of some window, or back down to the floor if there isn't one.
    func flyAround() {
        standUp(saying: false)
        if !flyToAWindow() { flyTo(floor(at: feet.x + (duck.facingLeft ? -200 : 200))) }
    }

    func jump() {
        guard !airborne else { return }
        standUp(saying: false)
        leavePerch()
        duck.set(.idle)
        soaring = false
        airborne = true
        velocity = CGVector(dx: duck.facingLeft ? -60 : 60, dy: 900)
        duck.set(.flying)
        Sounds.shared.play(.quack)
    }

    /// Comes over to where the mouse is: walks if it's along the floor, flies if it's up somewhere, and pops over
    /// if it's on another screen.
    func comeToMouse() {
        let mouse = NSEvent.mouseLocation
        guard !dragging else { return }
        if let there = NSScreen.screens.first(where: { $0.frame.contains(mouse) }), there != screen {
            dropIn(on: there, x: mouse.x)
            say(.summoned)
            return
        }
        if abs(mouse.y - feet.y) < 120, perch == nil, !airborne {
            walkTarget = min(max(mouse.x, screen.visibleFrame.minX + 60), screen.visibleFrame.maxX - 60)
        } else {
            let window = Desk.windows().first { $0.frame.minX < mouse.x && mouse.x < $0.frame.maxX && $0.frame.maxY < mouse.y + 200 }
            flyTo(window.flatMap { spot(on: $0, x: mouse.x) } ?? floor(at: mouse.x))
        }
    }

    /// Pops out of thin air at the top of a screen and drops to the floor.
    private func dropIn(on screen: NSScreen, x: CGFloat) {
        leavePerch()
        letGo = nil
        let frame = screen.visibleFrame
        feet = CGPoint(x: min(max(x, frame.minX + 60), frame.maxX - 60), y: ceiling(of: screen))
        velocity = .zero
        landing = nil
        onLand = nil
        walkTarget = nil
        soaring = false
        airborne = true
        duck.set(.flying)
        duck.spawn(.puff)
        place()
    }

    /// Sits down where it is and stays there until it's told something else. Hanging off a window, it lets go first.
    func sit() {
        walkTarget = nil
        moonwalking = false
        if hanging { letGoOfTheEdge() }
        duck.stay(true)
        if duck.isFree || duck.isDancing || duck.activity == .typing { duck.set(.idle) }
        duck.say(Lines.pick(.sit, prefs.personality, fill: ["user": prefs.userName]))
    }

    /// Gets back up after sitting.
    func standUp(saying: Bool = true) {
        guard duck.staying else { return }
        duck.stay(false)
        duck.hop()
        if saying { duck.say(Lines.pick(.stand, prefs.personality, fill: ["user": prefs.userName])) }
    }

    var isSitting: Bool { duck.staying }

    func toggleSit() {
        if duck.staying { standUp() } else { sit() }
    }

    func nap() {
        guard !airborne, !dragging else { return }
        walkTarget = nil
        duck.set(.sleeping)
    }

    /// Bring the duck to the screen the mouse is on, or over to the mouse if it's already there.
    func summon() {
        if !isVisible { show() }
        standUp(saying: false)
        comeToMouse()
    }

    private func letGoOfTheEdge() {
        guard hanging else { return }
        fallOff(say: nil, push: duck.facingLeft ? -40 : 40)
    }

    private func desktopChanged() {
        lastDeskSwitch = Date()
        guard isVisible, prefs.allDesktops else { return }
        // A window it was on is now on the other desktop; ride() notices and it falls. On the floor, it looks about.
        after(0.6) { [weak self] in
            guard let self, self.perch == nil, !self.airborne, self.duck.isFree,
                  Date().timeIntervalSince(self.lastDeskQuip) > 90, Int.random(in: 0..<3) == 0 else { return }
            self.lastDeskQuip = Date()
            self.duck.spawn(.question)
            self.duck.facingLeft.toggle()
            self.say(.newDesk)
        }
    }

    /// A screen was plugged in, unplugged or rearranged. If its screen went, the duck drops in on the main one.
    private func screensChanged() {
        litter.layout()
        guard isVisible, !onAScreen(feet), let main = NSScreen.main ?? NSScreen.screens.first else { return }
        dropIn(on: main, x: main.visibleFrame.midX)
    }

    /// Picks the top of a visible window and flies there. Returns false if there's nowhere good to go.
    @discardableResult
    private func flyToAWindow() -> Bool {
        let windows = Desk.windows()
        let visible = screen.visibleFrame
        var spots: [Spot] = []
        for (index, window) in windows.enumerated() where window.id != perch?.id && window.frame.width > 260 {
            let x = CGFloat.random(in: (window.frame.minX + 80)...(window.frame.maxX - 80))
            let edge = CGPoint(x: x, y: window.frame.maxY - 2)
            guard visible.contains(edge), let spot = spot(on: window, x: x),
                  !windows[..<index].contains(where: { $0.frame.contains(edge) }) else { continue }
            spots.append(spot)
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
        let x = window.map { min(max($0.frame.minX + 170, screen.visibleFrame.minX + 60), $0.frame.maxX - 80) } ?? feet.x
        guard let window, let spot = spot(on: window, x: x) else { return peckAndClose() }
        duck.stay(false)
        flyTo(spot)
        onLand = peckAndClose
    }

    /// Flies over to the front window and stands on it (or hangs off it), then does `work`.
    func visitFrontWindow(then work: @escaping @MainActor () -> Void) {
        guard let window = Desk.frontWindow(),
              let spot = spot(on: window, x: min(max(feet.x, window.frame.minX + 80), window.frame.maxX - 80)) else {
            return work()
        }
        flyTo(spot)
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
        } else if let since = typingSince, now.timeIntervalSince(since) > 2, [.idle, .walking, .sitting].contains(duck.activity) {
            walkTarget = nil
            duck.set(.typing)
        }
    }

    private func noticeAway() {
        let idle = Desk.idleSeconds
        let sleepAfter: TimeInterval = feelings.mood == .sleepy ? 60 : 180
        if idle > sleepAfter, [.idle, .petted, .sulking, .sitting].contains(duck.activity) {
            duck.set(.sleeping)
            feelings.feel(.userLeft)
        } else if idle < 2, duck.activity == .sleeping {
            duck.set(.idle)
            duck.hop()
            duck.wave()
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

        // On a call it keeps very still. Told to sit, on the tomato, or hanging on, it just enjoys it where it is.
        if duck.inMeeting { return }
        if duck.staying || hanging || duck.onTomato {
            if Int.random(in: 0..<2) == 0 { duck.spawn(.note) }
            return
        }
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
        // On the tomato: how long you've got left.
        if duck.onTomato, let timer = tomato {
            let minutes = max(1, Int((timer.until.timeIntervalSinceNow / 60).rounded(.up)))
            duck.quack()
            duck.say("\(minutes) minute\(minutes == 1 ? "" : "s") left. Back to work. 🍅")
            return
        }
        // On a call: a finger to the beak.
        if duck.inMeeting {
            duck.spawn(.shh)
            duck.hop()
            return
        }
        // Far too drunk to be poked.
        if booze.stage == .wasted, prefs.machineGun {
            if now.timeIntervalSince(lastBurst) > 1.5 { openFire() }
            return
        }
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
            moonwalking = false
            leavePerch()
            letGo = nil
            airborne = false
            soaring = false
            landing = nil
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

    // MARK: Pets, treats and the drink

    /// The mouse resting on the duck. A while of that is a pet, unless it's too drunk to be touched.
    private func beingPetted(for seconds: TimeInterval) {
        if booze.stage == .wasted {
            guard seconds > 0.3, duck.isFree || duck.activity == .sleeping, Date().timeIntervalSince(lastBurst) > 4 else { return }
            if prefs.machineGun {
                openFire()
            } else {
                lastBurst = Date()
                duck.spawn(.anger)
                say(.noPets)
            }
            return
        }
        guard seconds > 1.2, duck.isFree, duck.activity != .petted else { return }
        let wasDrunk = booze.stage > .sober
        duck.set(.petted)
        feelings.feel(.petted)
        booze.petted()
        duck.tipsy = booze.stage.rawValue
        if wasDrunk, Int.random(in: 0..<2) == 0 {
            say(.petSobers)
        } else if Int.random(in: 0..<3) == 0 {
            say(.pet)
        }
    }

    /// Cracks one open if it's due one and has nothing better to do.
    private func drinkIfThirsty() {
        booze.pass(1, youreAround: Desk.idleSeconds < 120, pace: prefs.drinking)
        if duck.activity == .sleeping { booze.sleep(1) }
        duck.tipsy = booze.stage.rawValue
        guard booze.thirsty, !airborne, !dragging, !talk.isOpen, [.idle, .walking, .sitting].contains(duck.activity) else { return }
        drink(given: false)
    }

    private func drink(given: Bool) {
        walkTarget = nil
        moonwalking = false
        duck.set(.drinking)
        Sounds.shared.play(.canOpen)
        after(2.3) { [weak self] in
            guard let self, self.duck.activity == .drinking else { return }
            let before = self.booze.stage
            self.booze.drank()
            self.duck.tipsy = self.booze.stage.rawValue
            self.feelings.feel(.drank)
            self.duck.set(.idle)
            // The empty goes over its shoulder.
            let toss = (self.duck.facingLeft ? 1 : -1) * CGFloat.random(in: 30...90)
            self.after(0.25) { [weak self] in
                guard let self else { return }
                self.litter.drop(near: self.feet.x + toss, on: self.screen)
                Sounds.shared.play(.clink)
            }
            switch self.booze.stage {
            case let now where now != before && now == .tipsy: self.say(.gotTipsy)
            case let now where now != before && now == .drunk: self.say(.gotDrunk)
            case let now where now != before && now == .wasted: self.say(.gotWasted)
            default: if given || Int.random(in: 0..<3) == 0 { self.say(.beer) }
            }
        }
    }

    /// Something to eat or drink, from you.
    func give(_ treat: Treat) {
        if !isVisible { show() }
        guard !airborne, !dragging, duck.activity != .shooting else { return }
        walkTarget = nil
        moonwalking = false
        switch treat {
        case .beer:
            guard booze.beers < Booze.most else {
                duck.say(Lines.pick(.tooMuch, prefs.personality))
                return
            }
            drink(given: true)
        case .bread:
            duck.set(.eating)
            Sounds.shared.play(.pop)
            after(2.2) { [weak self] in
                guard let self, self.duck.activity == .eating else { return }
                self.booze.soberUp(by: 1)
                self.duck.tipsy = self.booze.stage.rawValue
                self.feelings.feel(.fed)
                self.duck.spawn(.heart)
                self.duck.set(.celebrating)
                self.duck.say(Lines.pick(.bread, self.prefs.personality, fill: ["user": self.prefs.userName]))
                self.after(1.3) { [weak self] in if self?.duck.activity == .celebrating { self?.duck.set(.idle) } }
            }
        case .coffee:
            duck.set(.sipping)
            after(2.4) { [weak self] in
                guard let self, self.duck.activity == .sipping else { return }
                let wasDrunk = self.booze.stage > .sober
                self.booze.soberUp(by: 3)
                self.duck.tipsy = self.booze.stage.rawValue
                self.feelings.feel(.caffeinated)
                self.duck.spawn(.exclaim)
                self.duck.hop()
                self.duck.set(.idle)
                self.duck.say(Lines.pick(wasDrunk ? .soberedUp : .coffee, self.prefs.personality, fill: ["user": self.prefs.userName]))
            }
        }
    }

    /// Picks up the empty cans and cleans the poop off your windows.
    func cleanUp() {
        guard !litter.isEmpty || !droppings.isEmpty else { return }
        let cans = !litter.isEmpty
        litter.clear()
        droppings.clear()
        Sounds.shared.play(.pop)
        duck.spawn(.sparkle)
        duck.say(Lines.pick(cans ? (booze.stage > .sober ? .cansGoneDrunk : .cansGone) : .poopGone, prefs.personality))
    }

    /// Too drunk to be touched: out comes the machine gun, and the cursor gets blown across the screen.
    private func openFire() {
        lastBurst = Date()
        hoverSince = nil
        walkTarget = nil
        moonwalking = false
        let mouse = NSEvent.mouseLocation
        duck.facingLeft = mouse.x < feet.x
        duck.set(.shooting)
        Sounds.shared.play(.machineGun)
        feelings.feel(.firedGun)
        duck.say(Lines.pick(.machineGun, prefs.personality, fill: ["user": prefs.userName]), hold: 3)

        // Straight away from the duck, a good long way, staying on a screen.
        let head = CGPoint(x: feet.x, y: feet.y + spriteHeight * 0.45)
        var away = CGVector(dx: mouse.x - head.x, dy: mouse.y - head.y)
        let length = hypot(away.dx, away.dy)
        away = length < 1 ? CGVector(dx: duck.facingLeft ? -1 : 1, dy: 0.3) : CGVector(dx: away.dx / length, dy: away.dy / length)
        var target = CGPoint(x: mouse.x + away.dx * 520, y: mouse.y + away.dy * 520)
        if !onAScreen(target) {
            let frame = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? screen).frame.insetBy(dx: 12, dy: 12)
            target = CGPoint(x: min(max(target.x, frame.minX), frame.maxX), y: min(max(target.y, frame.minY), frame.maxY))
        }
        shove = (mouse, target, ProcessInfo.processInfo.systemUptime + 0.12)
        after(1.3) { [weak self] in if self?.duck.activity == .shooting { self?.duck.set(.idle) } }
    }

    /// Moves the cursor a little further along its way, juddering as the bullets hit it.
    private func blowCursorAway() {
        guard let shove else { return }
        let progress = (ProcessInfo.processInfo.systemUptime - shove.start) / 0.45
        guard progress >= 0 else { return }
        let t = CGFloat(min(1, progress))
        let eased = 1 - pow(1 - t, 3)
        let judder = 10 * (1 - t) * CGFloat(sin(Double(t) * 45))
        let along = CGVector(dx: shove.to.x - shove.from.x, dy: shove.to.y - shove.from.y)
        let length = max(1, hypot(along.dx, along.dy))
        let point = CGPoint(x: shove.from.x + along.dx * eased - along.dy / length * judder,
                            y: shove.from.y + along.dy * eased + along.dx / length * judder)
        // The cursor is placed from the top left of the main screen; AppKit counts from the bottom left.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: mainHeight - point.y))
        // Warping freezes the mouse for a moment unless it's tied back to the cursor.
        CGAssociateMouseAndMouseCursorPosition(1)
        if t >= 1 { self.shove = nil }
    }

    // MARK: Calls

    /// On a call, it puts on a tie, holds up the ON AIR sign and doesn't make a sound until it's over.
    private func noticeCall() {
        guard prefs.meetingMode || onACall, ProcessInfo.processInfo.environment["QUACKIE_DEMO"] != "meeting" else { return }
        let listening = talk.listening
        Task { [weak self] in
            let now = await Meetings.onACall(listening: listening)
            self?.callChanged(now && Settings.shared.prefs.meetingMode)
        }
    }

    /// For the demo: on a call for a while, whatever the camera says.
    func pretendCall(for seconds: TimeInterval) {
        callChanged(true)
        after(seconds) { [weak self] in self?.callChanged(false) }
    }

    private func callChanged(_ now: Bool) {
        guard now != onACall else { return }
        onACall = now
        if now {
            duck.hush()
            if hanging { letGoOfTheEdge() }
            walkTarget = nil
            moonwalking = false
            if duck.isDancing || duck.activity == .typing || duck.activity == .sleeping { duck.set(.idle) }
            Sounds.shared.hushed = true
            duck.meeting(true)
        } else {
            Sounds.shared.hushed = false
            duck.meeting(false)
            duck.hop()
            after(0.8) { [weak self] in self?.say(.meetingOver) }
        }
    }

    // MARK: The tomato timer

    var isTiming: Bool { tomato != nil }

    /// Starts the focus timer, or stops it if it's running.
    func toggleTomato() {
        if tomato != nil { stopTomato() } else { startTomato(round: 1) }
    }

    func startTomato(round: Int = 1) {
        if !isVisible { show() }
        standUp(saying: false)
        if hanging { letGoOfTheEdge() }
        walkTarget = nil
        moonwalking = false
        stretch = nil
        tomato = (false, Date().addingTimeInterval(Double(prefs.focusMinutes) * 60), round)
        if duck.isDancing || [.typing, .stretching, .sulking].contains(duck.activity) { duck.set(.idle) }
        duck.tomato(true)
        duck.hop()
        Sounds.shared.play(.pop)
        tickTomato()
        duck.say(Lines.pick(.tomatoStart, prefs.personality, fill: ["minutes": "\(prefs.focusMinutes)", "user": prefs.userName]))
    }

    /// For the demo: the bell goes now.
    func skipToBreak() {
        guard let timer = tomato, !timer.resting else { return }
        takeABreak(round: timer.round)
    }

    func stopTomato() {
        guard tomato != nil else { return }
        tomato = nil
        stretch = nil
        duck.tomato(false)
        onTimer?(nil)
        if duck.activity == .stretching { duck.set(.idle) }
        say(.tomatoStopped)
    }

    /// Once a second: the time left over its head, and the bell when it runs out.
    private func tickTomato() {
        guard let timer = tomato else { return }
        let left = max(0, Int(timer.until.timeIntervalSinceNow.rounded(.up)))
        onTimer?("\(timer.resting ? "☕️" : "🍅") \(left / 60):\(String(format: "%02d", left % 60))")
        if let stretch, duck.activity == .stretching, !stretch.joined, Desk.keyPresses &- stretch.keys > 25 {
            skippedStretch()
        }
        guard left == 0 else { return }
        if timer.resting { breakOver(round: timer.round) } else { takeABreak(round: timer.round) }
    }

    /// DING. Off the tomato and into some stretches, which you're meant to do too.
    private func takeABreak(round: Int) {
        let minutes = round % 4 == 0 ? prefs.breakMinutes * 3 : prefs.breakMinutes
        tomato = (true, Date().addingTimeInterval(Double(minutes) * 60), round)
        Sounds.shared.play(.ding)
        duck.tomato(false)
        // No stretching on camera.
        if airborne || dragging || duck.inMeeting { return }
        stretch = (false, Desk.keyPresses)
        if hanging { letGoOfTheEdge() }
        walkTarget = nil
        duck.set(.stretching)
        duck.say(Lines.pick(.tomatoBreak, prefs.personality, fill: ["user": prefs.userName]), choices: [
            .init(title: "Stretching with you 💪") { [weak self] in
                guard let self else { return }
                self.stretch?.joined = true
                self.duck.say(Lines.pick(.stretchYes, self.prefs.personality))
            },
            .init(title: "Skip") { [weak self] in self?.skippedStretch() },
        ], hold: 30)
        after(40) { [weak self] in self?.stretchesDone() }
    }

    private func stretchesDone() {
        guard let stretch, duck.activity == .stretching else { return }
        self.stretch = nil
        duck.set(.celebrating)
        duck.spawn(.sparkle)
        if stretch.joined {
            feelings.feel(.keptGoal)
            duck.say(Lines.pick(.stretchDone, prefs.personality, fill: ["user": prefs.userName]))
        }
        after(1.5) { [weak self] in if self?.duck.activity == .celebrating { self?.duck.set(.idle) } }
    }

    /// You didn't stretch. It noticed.
    private func skippedStretch() {
        guard stretch != nil else { return }
        stretch = nil
        feelings.feel(.snubbed)
        duck.facingLeft.toggle()
        duck.set(.sulking)
        duck.say(Lines.pick(.stretchSkipped, prefs.personality, fill: ["user": prefs.userName]))
        after(.random(in: 15...25)) { [weak self] in if self?.duck.activity == .sulking { self?.duck.set(.idle) } }
    }

    private func breakOver(round: Int) {
        tomato = nil
        stretch = nil
        onTimer?(nil)
        if duck.activity == .stretching { duck.set(.idle) }
        Sounds.shared.play(.ding)
        duck.say(Lines.pick(.tomatoBack, prefs.personality), choices: [
            .init(title: "Another round 🍅") { [weak self] in self?.startTomato(round: round + 1) },
            .init(title: "I'm done") { [weak self] in
                self?.duck.hush()
                self?.say(.tomatoStopped)
            },
        ], hold: 60)
    }

    // MARK: Poop

    /// Flies onto the front window, leaves it a little something, and says `line`.
    func poop(saying line: String) {
        guard !airborne, !dragging, !duck.isBusy, !duck.inMeeting else { return duck.say(line) }
        standUp(saying: false)
        walkTarget = nil
        moonwalking = false
        visitFrontWindow { [weak self] in
            guard let self else { return }
            self.duck.set(.pooping)
            self.after(1.2) { [weak self] in
                guard let self, self.duck.activity == .pooping else { return }
                // Out the back end, which is whichever way it isn't facing.
                let behind = self.feet.x + (self.duck.facingLeft ? 1 : -1) * 18 * self.pixel
                self.droppings.drop(on: self.perch, x: behind, floor: CGPoint(x: behind, y: self.feet.y))
                Sounds.shared.play(.splat)
                self.duck.spawn(.stink, at: CGPoint(x: self.duck.facingLeft ? 50 : 8, y: 44))
                self.after(0.6) { [weak self] in
                    guard let self else { return }
                    self.duck.set(.idle)
                    self.duck.say(line)
                }
            }
        }
    }

    // MARK: Birthdays

    /// Cake, party horn, confetti.
    func party(for seconds: TimeInterval = 6) {
        guard !airborne, !dragging, !duck.inMeeting else { return }
        if hanging {
            // Not while holding on by one wing: down first, then the cake.
            letGoOfTheEdge()
            onLand = { [weak self] in self?.party(for: seconds) }
            return
        }
        standUp(saying: false)
        walkTarget = nil
        duck.set(.partying)
        Sounds.shared.play(.partyHorn)
        feelings.feel(.bananas)
        after(1.6) { [weak self] in if self?.duck.activity == .partying { Sounds.shared.play(.partyHorn) } }
        after(seconds) { [weak self] in if self?.duck.activity == .partying { self?.duck.set(.idle) } }
    }

    // MARK: Human hunt

    /// The Konami code: the tables turn, and the duck hunts your cursor for twenty seconds.
    func huntHuman() {
        if !isVisible { show() }
        guard hunt == nil, !airborne, !dragging, !duck.inMeeting else { return }
        if hanging {
            letGoOfTheEdge()
            onLand = { [weak self] in self?.huntHuman() }
            return
        }
        standUp(saying: false)
        walkTarget = nil
        moonwalking = false
        talk.close()
        let start = CGPoint(x: feet.x + 20 * pixel, y: feet.y + spriteHeight * 0.4)
        hunt = (start, 0, 0, 0, Date().addingTimeInterval(1.5), Date().addingTimeInterval(21.5))
        crosshair.show(at: start)
        duck.set(.hunting)
        Sounds.shared.play(.cock)
        duck.say(Lines.pick(.huntStart, prefs.personality, fill: ["user": prefs.userName]), alarm: true, hold: 3)
    }

    /// Steers the crosshair after the cursor, a little faster as time goes on, and fires once it's held on.
    private func chase(_ mouse: CGPoint, _ dt: TimeInterval) {
        guard var game = hunt else { return }
        let now = Date()
        if now > game.ends || duck.activity != .hunting { return endHunt() }
        guard now > game.starts else { return }
        let elapsed = now.timeIntervalSince(game.starts)
        let speed = CGFloat(2.2 + elapsed * 0.22)
        let follow = min(1, speed * CGFloat(dt))
        game.at = CGPoint(x: game.at.x + (mouse.x - game.at.x) * follow, y: game.at.y + (mouse.y - game.at.y) * follow)
        let onTarget = hypot(mouse.x - game.at.x, mouse.y - game.at.y) < 16
        game.lockedOn = onTarget ? game.lockedOn + dt : max(0, game.lockedOn - dt)
        let clock = ProcessInfo.processInfo.systemUptime
        if game.lockedOn > 0.4, clock - game.lastShot > 0.9 {
            game.lastShot = clock
            game.lockedOn = 0
            game.hits += 1
            duck.bang()
            duck.spawn(.laugh)
            crosshair.flash()
            Sounds.shared.play(.gunshot)
            if game.hits % 3 == 1 { duck.say(Lines.pick(.huntHit, prefs.personality), hold: 1.5) }
        }
        crosshair.move(to: game.at)
        hunt = game
    }

    private func endHunt() {
        guard let game = hunt else { return }
        hunt = nil
        crosshair.hide()
        duck.set(game.hits > 0 ? .celebrating : .sulking)
        if game.hits > 0 { duck.spawn(.laugh); feelings.feel(.firedGun) }
        duck.say(Lines.pick(game.hits > 0 ? .huntOver : .huntMissed, prefs.personality,
                            fill: ["hits": "\(game.hits)", "user": prefs.userName]))
        after(2.5) { [weak self] in
            if self?.duck.activity == .celebrating || self?.duck.activity == .sulking { self?.duck.set(.idle) }
        }
    }

    // MARK: Visitors

    /// Asks a friend over. Down to the floor first, if it's up on a window.
    func inviteFriend() {
        if !isVisible { show() }
        guard visitor == nil, !airborne, !dragging, !duck.inMeeting, hunt == nil else { return }
        standUp(saying: false)
        if perch != nil || hanging {
            flyTo(floor(at: feet.x))
            onLand = { [weak self] in self?.friendDropsBy() }
            return
        }
        friendDropsBy()
    }

    /// Another duck flies in, the two of them gossip about you, and then they fight. The guest always leaves.
    private func friendDropsBy() {
        guard visitor == nil, perch == nil, !airborne else { return }
        lastVisit = Date()
        walkTarget = nil
        moonwalking = false
        if duck.activity != .idle, duck.isFree { duck.set(.idle) }
        let visible = screen.visibleFrame
        // It lands on whichever side has more room.
        let side: CGFloat = feet.x - visible.minX > visible.maxX - feet.x ? -1 : 1
        let gap = 44 * pixel
        if (side < 0 && feet.x - gap < visible.minX + 40) || (side > 0 && feet.x + gap > visible.maxX - 40) { return }
        let spot = CGPoint(x: feet.x + side * gap, y: feet.y)
        let entrance = CGPoint(x: side < 0 ? visible.minX - 120 : visible.maxX + 120, y: feet.y + 260)
        let guest = Visitor(not: prefs.skin, from: entrance)
        visitor = guest
        duck.facingLeft = side < 0
        duck.spawn(.question)
        guest.arrive(at: spot) { [weak self, weak guest] in
            guard let self, let guest else { return }
            guest.duck.facingLeft = side > 0
            self.duck.facingLeft = side < 0
            let fill = ["user": self.prefs.userName, "name": self.prefs.duckName, "friend": guest.skin.name,
                        "app": NSWorkspace.shared.frontmostApplication?.localizedName ?? "the internet"]
            self.gossip(Lines.gossip.randomElement() ?? [], fill: fill, with: guest, exit: entrance)
        }
    }

    private func gossip(_ script: [(mine: Bool, line: String)], fill: [String: String], with guest: Visitor, exit: CGPoint) {
        guard let (mine, raw) = script.first else { return fight(guest, exit: exit) }
        var line = raw
        for (key, value) in fill { line = line.replacingOccurrences(of: "{\(key)}", with: value.isEmpty ? "your human" : value) }
        if mine {
            guest.duck.hush()
            duck.say(prefs.personality == .sergeant ? line.uppercased() : line, hold: 3)
        } else {
            duck.hush()
            guest.duck.say(guest.personality == .sergeant ? line.uppercased() : line, hold: 3)
        }
        let pause = min(4, 1.6 + Double(line.count) * 0.04)
        after(pause) { [weak self] in self?.gossip(Array(script.dropFirst()), fill: fill, with: guest, exit: exit) }
    }

    /// A brawl in a cloud of feathers, then one of them comes off worse and the guest flies off.
    private func fight(_ guest: Visitor, exit: CGPoint) {
        duck.hush()
        guest.duck.hush()
        duck.set(.fighting)
        guest.duck.set(.fighting)
        feelings.feel(.landedHard)
        for beat in 0..<10 {
            after(Double(beat) * 0.32) { [weak guest] in
                Sounds.shared.play([.thud, .pop, .quack].randomElement()!)
                guest?.shove(by: beat % 2 == 0 ? 6 : -6)
            }
        }
        after(3.4) { [weak self] in
            guard let self else { return }
            let won = Bool.random()
            guest.duck.set(won ? .dizzy : .celebrating)
            self.duck.set(won ? .celebrating : .dizzy)
            if !won { Sounds.shared.play(.thud) }
            self.say(won ? .friendWon : .friendLost)
            self.after(2) { [weak self] in
                guard let self else { return }
                guest.leave(to: exit) { [weak self] in
                    guard let self else { return }
                    self.visitor = nil
                    if [.celebrating, .dizzy].contains(self.duck.activity) { self.duck.set(.idle) }
                    if Int.random(in: 0..<2) == 0 { self.say(.friendGone) }
                }
            }
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
        guard !duck.inMeeting, !duck.isBusy || [.thrown, .windowGone, .grabbed, .windowYanked, .takeOff, .newDesk, .summoned].contains(moment),
              !talk.isOpen else { return }
        duck.say(Lines.pick(moment, prefs.personality, fill: fill.merging(["user": prefs.userName]) { $1 }))
    }

    private func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            await work()
        }
    }
}
