import AppKit
import CoreGraphics

/// Cheap things the duck can notice without any permission: how fast you're typing, whether you've gone
/// away, and where the front window is.
enum Desk {
    /// Every key press since you logged in. Only a count: which keys you press stays private.
    static var keyPresses: UInt32 {
        CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
    }

    /// Seconds since you last touched the keyboard, mouse or trackpad.
    static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    struct Window: Equatable {
        let id: CGWindowID
        let pid: pid_t
        /// In AppKit screen coordinates (origin at the bottom left of the main screen).
        let frame: CGRect
    }

    /// The front app's frontmost normal window.
    static func frontWindow() -> Window? {
        guard let app = Eyes.frontApp(),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        return list.lazy.compactMap(window).first { $0.pid == app.processIdentifier }
    }

    /// Every normal window on screen, front to back (not the duck's own).
    static func windows() -> [Window] {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap(window).filter { $0.pid != me }
    }

    /// Where a window is now, or nil if it closed, minimised or moved to another Space.
    static func window(_ id: CGWindowID) -> Window? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let info = list.first, info[kCGWindowIsOnscreen as String] as? Bool == true
        else { return nil }
        return window(info)
    }

    private static func window(_ info: [String: Any]) -> Window? {
        guard info[kCGWindowLayer as String] as? Int == 0,
              let id = info[kCGWindowNumber as String] as? CGWindowID,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds),
              rect.width > 200, rect.height > 120
        else { return nil }
        // Window bounds are measured from the top left of the main screen; AppKit's from the bottom left.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return Window(id: id, pid: pid, frame: CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height))
    }
}
