import AppKit
import ApplicationServices

/// The duck's wings on your mouse: moving, clicking, dragging and scrolling, for when it flies around your
/// screen doing a task for you. Needs Accessibility.
///
/// Points are in Quartz's global space: top-left of the main display, y down (what CGEvent and screenshots
/// use). The duck's own window lives in AppKit's space (bottom-left, y up); `appKit(_:)` converts.
enum Wings {
    private static let source = CGEventSource(stateID: .hidSystemState)

    /// Where the real pointer is right now, in Quartz space.
    static var pointer: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// Puts the real pointer back where you left it.
    static func warp(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    static func appKit(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: mainHeight - point.y)
    }

    static func quartz(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: mainHeight - point.y)
    }

    private static var mainHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    // MARK: Mouse

    static func move(to point: CGPoint) {
        post(.mouseMoved, at: point, button: .left)
    }

    static func click(at point: CGPoint, right: Bool = false, count: Int = 1) async {
        let down: CGEventType = right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = right ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = right ? .right : .left
        post(.mouseMoved, at: point, button: button)
        try? await Task.sleep(for: .milliseconds(40))
        for i in 1...max(1, count) {
            post(down, at: point, button: button, clickState: i)
            try? await Task.sleep(for: .milliseconds(35))
            post(up, at: point, button: button, clickState: i)
            if i < count { try? await Task.sleep(for: .milliseconds(80)) }
        }
    }

    static func dragBegin(at point: CGPoint) {
        post(.mouseMoved, at: point, button: .left)
        post(.leftMouseDown, at: point, button: .left, clickState: 1)
    }

    static func dragMove(to point: CGPoint) {
        post(.leftMouseDragged, at: point, button: .left)
    }

    static func dragEnd(at point: CGPoint) {
        post(.leftMouseUp, at: point, button: .left, clickState: 1)
    }

    /// Scrolls smoothly at a point. Positive `dy` scrolls the page down, positive `dx` scrolls right.
    static func scroll(dx: Int, dy: Int, at point: CGPoint) async {
        post(.mouseMoved, at: point, button: .left)
        let steps = 12
        for _ in 0..<steps {
            let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                wheel1: Int32(-dy / steps), wheel2: Int32(-dx / steps), wheel3: 0)
            event?.location = point
            event?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private static func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton, clickState: Int = 0) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        if clickState > 0 { event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState)) }
        event?.flags = []
        event?.post(tap: .cghidEventTap)
    }
}

/// Reads things through Accessibility that pixels can't tell you: what the controls under a point are called,
/// where typing will go, and whether that's a password field.
enum Feel {
    struct Control: Sendable {
        let role: String
        let label: String
        /// Quartz space.
        let frame: CGRect
    }

    private static let roles: [String: String] = [
        "AXButton": "button", "AXMenuButton": "menu button", "AXPopUpButton": "pop-up", "AXCheckBox": "checkbox",
        "AXRadioButton": "option", "AXTextField": "text field", "AXTextArea": "text area", "AXComboBox": "combo box",
        "AXSearchField": "search field", "AXLink": "link", "AXSlider": "slider", "AXTab": "tab",
        "AXMenuItem": "menu item", "AXMenuBarItem": "menu", "AXDisclosureTriangle": "disclosure", "AXCell": "cell",
        "AXImage": "image", "AXStaticText": "text", "AXHeading": "heading",
    ]

    /// The focused element of the front app: where typing goes, and whether it's a password field.
    static func focusedField() -> (frame: CGRect?, secure: Bool, label: String?) {
        guard AXIsProcessTrusted(), let app = Eyes.frontApp() else { return (nil, false, nil) }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        guard let focused: AXUIElement = attribute(element, kAXFocusedUIElementAttribute) else { return (nil, false, nil) }
        let subrole: String = attribute(focused, kAXSubroleAttribute) ?? ""
        return (frame(of: focused), subrole == "AXSecureTextField", describe(focused))
    }

    /// The control at a point on screen (Quartz space), if it can be read.
    static func control(at point: CGPoint) -> Control? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, var element = hit else {
            return nil
        }
        // Walk up to the nearest thing with a name, so a click on a button's label reads as the button.
        for _ in 0..<4 {
            let role: String = attribute(element, kAXRoleAttribute) ?? ""
            if let kind = roles[role], let label = describe(element), let frame = frame(of: element) {
                return Control(role: kind, label: label, frame: frame)
            }
            guard let parent: AXUIElement = attribute(element, kAXParentAttribute) else { break }
            element = parent
        }
        return nil
    }

    /// Selected text in the front app, if any. Lets "what does this mean?" be about what you highlighted.
    static func selectedText() -> String? {
        guard AXIsProcessTrusted(), let app = Eyes.frontApp() else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        guard let focused: AXUIElement = attribute(element, kAXFocusedUIElementAttribute),
              let text: String = attribute(focused, kAXSelectedTextAttribute) else { return nil }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(800))
    }

    /// The named controls in the front window, top to bottom, within a small time budget.
    static func controls(of pid: pid_t, limit: Int = 60, budget: TimeInterval = 0.35) -> [Control] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        // Electron apps (Slack, VS Code, Discord…) only expose their controls when asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let window: AXUIElement = attribute(app, kAXFocusedWindowAttribute) else { return [] }
        let deadline = Date().addingTimeInterval(budget)
        var queue = [window]
        var found: [Control] = []
        var seen = Set<String>()
        var visited = 0
        let clickable: Set<String> = ["button", "menu button", "pop-up", "checkbox", "option", "text field", "text area",
                                      "combo box", "search field", "link", "slider", "tab", "disclosure"]
        while !queue.isEmpty, visited < 3000, Date() < deadline {
            let element = queue.removeFirst()
            visited += 1
            let role: String = attribute(element, kAXRoleAttribute) ?? ""
            let subrole: String = attribute(element, kAXSubroleAttribute) ?? ""
            if let kind = roles[subrole == "AXSearchField" ? "AXSearchField" : role], clickable.contains(kind),
               let rect = frame(of: element), rect.width > 3, rect.height > 3 {
                let label = describe(element) ?? ""
                let key = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width))"
                if !label.isEmpty || kind.contains("field"), !seen.contains(key) {
                    seen.insert(key)
                    found.append(Control(role: kind, label: label, frame: rect))
                }
            }
            if let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) {
                queue.append(contentsOf: children.prefix(300))
            }
        }
        found.sort { abs($0.frame.minY - $1.frame.minY) > 6 ? $0.frame.minY < $1.frame.minY : $0.frame.minX < $1.frame.minX }
        return Array(found.prefix(limit))
    }

    private static func describe(_ element: AXUIElement) -> String? {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue", kAXValueAttribute, kAXHelpAttribute] {
            if let text: String = attribute(element, key) {
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
                if !clean.isEmpty { return String(clean.prefix(60)) }
            }
        }
        return nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = attribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self {
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement) as? T
        }
        if T.self == AXValue.self {
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            return (value as! AXValue) as? T
        }
        if T.self == [AXUIElement].self {
            guard let array = value as? [AnyObject] else { return nil }
            return array.compactMap { item -> AXUIElement? in
                CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
            } as? T
        }
        return value as? T
    }
}
