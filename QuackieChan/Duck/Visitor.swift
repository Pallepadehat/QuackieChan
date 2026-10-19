import AppKit
import SwiftUI

/// Another duck dropping by. It flies in from the edge of the screen, lands next to yours, says its piece and flies
/// off again. What the two of them get up to in between is up to your duck's window (DuckWindow.friendDropsBy).
/// It's only a guest: one see-through window with the duck and its bubble, and clicks go straight through.
@MainActor
final class Visitor {
    let duck = Duck()
    let skin: DuckSkin
    let personality: Personality
    /// Where its feet are, in screen coordinates.
    private(set) var feet: CGPoint

    private let panel: NSPanel
    private var ticker: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    /// The flight it's on: from, to, how long, when it started, and what happens on arrival.
    private var flight: (from: CGPoint, to: CGPoint, length: TimeInterval, start: TimeInterval, then: (() -> Void)?)?
    private var pixel: CGFloat { Settings.shared.prefs.size.pixel }

    private static let bubbleHeight: CGFloat = 150

    init(not host: DuckSkin, from start: CGPoint) {
        skin = DuckSkin.all.filter { $0.id != host.id }.randomElement() ?? .standard
        personality = Personality.allCases.randomElement() ?? .unhinged
        feet = start
        let stage = DuckStage.size(pixel: Settings.shared.prefs.size.pixel)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: max(stage.width, 290), height: stage.height + Self.bubbleHeight),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = DuckWindow.behavior
        panel.contentView = NSHostingView(rootView: VisitorStage(duck: duck, skin: skin, name: skin.name))
        let personality = personality
        duck.onSay = { line in Sounds.shared.babble(line, personality: personality) }
    }

    func arrive(at spot: CGPoint, then: @escaping () -> Void) {
        place()
        panel.orderFrontRegardless()
        duck.facingLeft = spot.x < feet.x
        duck.set(.soaring)
        Sounds.shared.play(.whoosh)
        fly(to: spot, length: 1.3) { [weak self] in
            self?.duck.set(.idle)
            self?.duck.hop()
            then()
        }
        start()
    }

    func leave(to spot: CGPoint, then: (() -> Void)? = nil) {
        duck.hush()
        duck.facingLeft = spot.x < feet.x
        duck.set(.soaring)
        Sounds.shared.play(.whoosh)
        fly(to: spot, length: 1.2) { [weak self] in
            self?.close()
            then?()
        }
    }

    func close() {
        ticker?.invalidate()
        ticker = nil
        panel.orderOut(nil)
    }

    /// Shuffles sideways a little, for the fight.
    func shove(by dx: CGFloat) { feet.x += dx }

    private func fly(to spot: CGPoint, length: TimeInterval, then: (() -> Void)?) {
        flight = (feet, spot, length, ProcessInfo.processInfo.systemUptime, then)
    }

    private func start() {
        ticker?.invalidate()
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        duck.step(by: min(0.1, now - lastTick))
        lastTick = now
        if let flight {
            // A swoop: straight across, with an arc on top.
            let t = min(1, (now - flight.start) / flight.length)
            let eased = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
            feet = CGPoint(x: flight.from.x + (flight.to.x - flight.from.x) * eased,
                           y: flight.from.y + (flight.to.y - flight.from.y) * eased + 120 * CGFloat(sin(.pi * t)))
            if t >= 1 {
                self.flight = nil
                flight.then?()
            }
        }
        place()
    }

    private func place() {
        let size = panel.frame.size
        let origin = NSPoint(x: (feet.x - size.width / 2).rounded(), y: (feet.y - 2 * pixel).rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }
}

/// The visiting duck, with its speech bubble over its head.
private struct VisitorStage: View {
    let duck: Duck
    let skin: DuckSkin
    let name: String
    @Bindable var settings = Settings.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if let bubble = duck.bubble {
                SpeechBubble(bubble: bubble, name: name, tailShift: (duck.facingLeft ? -8 : 8) * settings.prefs.size.pixel)
                    .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                    .id(bubble.id)
                    .padding(.bottom, -CGFloat(DuckArt.canvasHeight) * settings.prefs.size.pixel * 0.22)
                    .zIndex(1)
            }
            DuckFigure(duck: duck, skin: skin, pixel: settings.prefs.size.pixel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(duration: 0.25, bounce: 0.45), value: duck.bubble?.id)
    }
}
