import AppKit
import SwiftUI

/// ↑ ↑ ↓ ↓ ← → ← → B A, typed while Quackie Chan is in front (the talk box or settings). Only the duck's own
/// windows are listened to, so what you type elsewhere stays private.
@MainActor
final class KonamiCode {
    private static let sequence: [UInt16] = [126, 126, 125, 125, 123, 124, 123, 124, 11, 0]
    private var typed: [UInt16] = []
    private var monitor: Any?

    init(onEntered: @escaping @MainActor () -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let key = event.keyCode
            let entered = MainActor.assumeIsolated { self?.pressed(key) ?? false }
            if entered { MainActor.assumeIsolated { onEntered() } }
            return entered ? nil : event
        }
    }

    /// True when `key` finishes the code.
    private func pressed(_ key: UInt16) -> Bool {
        typed = Array((typed + [key]).suffix(Self.sequence.count))
        guard typed == Self.sequence else { return false }
        typed.removeAll()
        return true
    }
}

/// The crosshair in the reverse Duck Hunt: a pixel reticle in its own little see-through window that the duck
/// steers toward your cursor. It never touches the cursor; it just hunts it.
@MainActor
final class Crosshair {
    @MainActor
    @Observable
    final class Look {
        var hit = false
    }

    private let panel: NSPanel
    private let look = Look()
    static let size: CGFloat = 54

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: Reticle(look: look))
    }

    func show(at point: CGPoint) {
        move(to: point)
        panel.orderFrontRegardless()
    }

    func move(to point: CGPoint) {
        panel.setFrameOrigin(NSPoint(x: (point.x - Self.size / 2).rounded(), y: (point.y - Self.size / 2).rounded()))
    }

    func hide() { panel.orderOut(nil) }

    /// Flashes white for a hit.
    func flash() {
        look.hit = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [look] in look.hit = false }
    }
}

/// A chunky pixel reticle, like the one in the old light-gun games.
private struct Reticle: View {
    let look: Crosshair.Look

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 18
            let color: Color = look.hit ? .white : Color(red: 0.95, green: 0.2, blue: 0.2)
            func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ fill: Color) {
                context.fill(Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: CGFloat(w) * unit, height: CGFloat(h) * unit)),
                             with: .color(fill))
            }
            // Dark edges first, so it shows on light and dark windows alike.
            for (x, y, w, h) in [(2, 2, 14, 2), (2, 14, 14, 2), (2, 2, 2, 14), (14, 2, 2, 14), (8, 0, 2, 7), (8, 11, 2, 7), (0, 8, 7, 2), (11, 8, 7, 2)] {
                box(x, y, w, h, .black.opacity(0.55))
            }
            for (x, y, w, h) in [(3, 3, 12, 1), (3, 14, 12, 1), (3, 3, 1, 12), (14, 3, 1, 12), (8, 1, 2, 5), (8, 12, 2, 5), (1, 8, 5, 2), (12, 8, 5, 2)] {
                box(x, y, w, h, color)
            }
            box(8, 8, 2, 2, color)
        }
        .frame(width: Crosshair.size, height: Crosshair.size)
    }
}
