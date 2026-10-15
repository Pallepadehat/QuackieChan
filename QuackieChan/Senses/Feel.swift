import AppKit
import ApplicationServices

/// Reads things through Accessibility that pixels can't tell you: what the controls under a point are called,
/// where typing will go, and whether that's a password field.
enum Feel {
    /// Where your pointer is right now: top-left of the main display, y down (like screenshots and window frames).
    static var pointer: CGPoint { CGEvent(source: nil)?.location ?? .zero }

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

    /// The control at a point on screen (Quartz space), if it can be read and doesn't belong to an app in `hidden`
    /// (bundle IDs the duck must never look at).
    static func control(at point: CGPoint, hiding hidden: Set<String> = []) -> Control? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, var element = hit else {
            return nil
        }
        // A password manager's panel can sit under the pointer without being the front app.
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier,
              !hidden.contains(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "") else { return nil }
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
