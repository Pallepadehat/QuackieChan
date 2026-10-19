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

/// A pixel-art can, drawn square pixel by square pixel in the duck's colours.
private struct CanSprite: View {
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
