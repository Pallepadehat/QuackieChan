import AppKit
import Observation
import SwiftUI

/// The empty beer cans the duck leaves on the floor. Each screen with cans on it gets a see-through strip along
/// the bottom (clicks go straight through it) where they lie until you tidy up. They're kept between launches.
@MainActor
final class Litter {
    static let shared = Litter()

    struct Can: Codable, Identifiable, Equatable {
        var id = UUID()
        /// Points from the left of its screen's visible area.
        var x: CGFloat
        var display: CGDirectDisplayID
        var kind: Int
        var flipped: Bool
    }

    @MainActor
    @Observable
    final class Pile {
        var cans: [Can] = []
    }

    let pile = Pile()
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var showing = false
    private static let key = "litter.cans"
    /// Old cans get cleared away when there are too many to look at.
    private static let most = 24

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let cans = try? JSONDecoder().decode([Can].self, from: data) {
            pile.cans = cans
        }
    }

    var isEmpty: Bool { pile.cans.isEmpty }

    /// Drops an empty can on the floor of `screen`, near `x` in screen coordinates.
    func drop(near x: CGFloat, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let local = min(max(x - visible.minX, 16), visible.width - 16)
        // Crushed or on its side more often than standing: it's had a few.
        let kind = [0, 1, 1, 2, 2].randomElement()!
        pile.cans.append(Can(x: local, display: screen.displayID, kind: kind, flipped: Bool.random()))
        if pile.cans.count > Self.most { pile.cans.removeFirst(pile.cans.count - Self.most) }
        save()
        layout()
    }

    func clear() {
        withAnimation(.easeIn(duration: 0.25)) { pile.cans.removeAll() }
        save()
        // Let them fade before their strips go.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.layout() }
    }

    func show() {
        showing = true
        layout()
    }

    func hide() {
        showing = false
        layout()
    }

    /// Puts a strip on every screen that has cans, and takes it off the ones that don't. Cans left on a screen
    /// that's been unplugged move to the main one.
    func layout() {
        let screens = NSScreen.screens
        if let main = screens.first {
            let known = Set(screens.map(\.displayID))
            for index in pile.cans.indices where !known.contains(pile.cans[index].display) {
                pile.cans[index].display = main.displayID
            }
        }
        let wanted = showing ? Set(pile.cans.map(\.display)) : []
        for (display, panel) in panels where !wanted.contains(display) {
            panel.orderOut(nil)
            panels[display] = nil
        }
        let pixel = Settings.shared.prefs.size.pixel
        for screen in screens where wanted.contains(screen.displayID) {
            let visible = screen.visibleFrame
            // A pixel lower than the floor, so the cans' outlines line up with the duck's feet.
            let frame = NSRect(x: visible.minX, y: visible.minY - pixel, width: visible.width, height: 14 * pixel)
            let panel = panels[screen.displayID] ?? makePanel(for: screen.displayID)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            panel.collectionBehavior = DuckWindow.behavior
            panel.orderFrontRegardless()
        }
    }

    private func makePanel(for display: CGDirectDisplayID) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: LitterView(pile: pile, display: display))
        panels[display] = panel
        return panel
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pile.cans) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// The cans on one screen's floor.
private struct LitterView: View {
    let pile: Litter.Pile
    let display: CGDirectDisplayID
    @Bindable var settings = Settings.shared

    var body: some View {
        let pixel = settings.prefs.size.pixel
        ZStack(alignment: .bottomLeading) {
            Color.clear
            ForEach(pile.cans.filter { $0.display == display }) { can in
                let rows = CanArt.rows(can.kind)
                let width = CGFloat(rows[0].count) * pixel
                CanSprite(rows: rows)
                    .frame(width: width, height: CGFloat(rows.count) * pixel)
                    .scaleEffect(x: can.flipped ? -1 : 1, y: 1)
                    .offset(x: can.x - width / 2)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .scale(scale: 0.2, anchor: .bottom).combined(with: .opacity)))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.5), value: pile.cans)
    }
}

/// Pixel art from rows of palette letters (a can, a poop), drawn square pixel by square pixel in the duck's colours.
struct CanSprite: View {
    let rows: [String]
    private static let palette = Plumage.classic.palette

    var body: some View {
        Canvas { context, size in
            let pixel = size.width / CGFloat(rows[0].count)
            for (y, row) in rows.enumerated() {
                for (x, character) in row.enumerated() {
                    guard let color = Self.palette[character] else { continue }
                    let rect = CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel)
                    context.fill(Path(rect), with: .color(Color(cgColor: color.cgColor)))
                }
            }
        }
    }
}

extension NSScreen {
    /// Stays the same for a display while it's plugged in, unlike its place in `NSScreen.screens`.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// What the duck leaves on the window you've been doomscrolling on: a pixel poop just inside its top edge (below
/// where the duck stood, and clear of the menu bar on full-height windows) that rides along when you move the
/// window, hides when another window covers it, and goes when the window does. Only kept while the app runs.
@MainActor
final class Droppings {
    static let shared = Droppings()

    private struct Poop {
        let window: CGWindowID?
        /// Points from the window's left edge, or the screen point it sits on when it's on the floor.
        let offset: CGFloat
        let floor: CGPoint?
        let panel: NSPanel
    }

    private var poops: [Poop] = []
    /// How far below the window's top edge it lands, past the title bar.
    private static let drop: CGFloat = 40
    private var timer: Timer?
    private var showing = true

    var isEmpty: Bool { poops.isEmpty }

    /// Drops one on top of `window` at `x` (screen coordinates), or on the floor at `point` without a window.
    func drop(on window: Desk.Window?, x: CGFloat, floor point: CGPoint) {
        let pixel = Settings.shared.prefs.size.pixel
        let rows = PoopArt.rows
        let size = NSSize(width: CGFloat(rows[0].count) * pixel, height: CGFloat(rows.count) * pixel)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = DuckWindow.behavior
        panel.contentView = NSHostingView(rootView: PoopSprite())
        poops.append(Poop(window: window?.id, offset: window.map { x - $0.frame.minX } ?? 0,
                          floor: window == nil ? point : nil, panel: panel))
        if poops.count > 12 { poops.removeFirst().panel.orderOut(nil) }
        update()
        if timer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func clear() {
        for poop in poops {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; poop.panel.animator().alphaValue = 0 } completionHandler: {
                poop.panel.orderOut(nil)
            }
        }
        poops.removeAll()
        timer?.invalidate()
        timer = nil
    }

    func show() { showing = true; update() }
    func hide() { showing = false; update() }

    /// Keeps each poop on its window's top edge, showing only the ones you could actually see.
    private func update() {
        let windows = Desk.windows()
        for poop in poops {
            let size = poop.panel.frame.size
            var origin: CGPoint?
            if let point = poop.floor {
                origin = CGPoint(x: point.x - size.width / 2, y: point.y)
            } else if let index = windows.firstIndex(where: { $0.id == poop.window }) {
                let frame = windows[index].frame
                let x = min(max(frame.minX + poop.offset, frame.minX + size.width), frame.maxX - size.width)
                let bottom = frame.maxY - Self.drop - size.height
                let middle = CGPoint(x: x, y: bottom + size.height / 2)
                // Hidden behind a window in front of this one.
                if !windows[..<index].contains(where: { $0.frame.contains(middle) }) {
                    origin = CGPoint(x: x - size.width / 2, y: bottom)
                }
            }
            guard showing, let origin else {
                if poop.panel.isVisible { poop.panel.orderOut(nil) }
                continue
            }
            let rounded = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
            if poop.panel.frame.origin != rounded { poop.panel.setFrameOrigin(rounded) }
            if !poop.panel.isVisible { poop.panel.orderFrontRegardless() }
        }
    }
}

nonisolated enum PoopArt {
    static let rows = [
        "....O....",
        "...OTO...",
        "..OTTtO..",
        ".OOTwTOO.",
        "OTTTTTTtO",
        "OTwTTTTtO",
        ".OOOOOOO.",
    ]
}

/// The poop, square pixel by square pixel.
private struct PoopSprite: View {
    var body: some View {
        CanSprite(rows: PoopArt.rows)
    }
}
