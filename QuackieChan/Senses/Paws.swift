import AppKit
import Carbon.HIToolbox

/// Something the duck can do on your Mac when you ask.
nonisolated enum Deed: Equatable, Sendable {
    case open(String), quit(String), hide(String), focus(String)
    case play(String?), pause, next, previous
    case volume(Int), louder, quieter, mute
    case website(String), search(String)
    case closeTab, newTab, reload, closeWindow, minimize, fullscreen
    case press(String), type(String)
    case darkMode(Bool?)
    case remind(minutes: Int, about: String)
    case dance, nap

    /// Things you'd want to be asked about first.
    var isDrastic: Bool {
        switch self {
        case .quit, .closeTab, .closeWindow, .press, .type: true
        default: false
        }
    }

    /// Needs Accessibility (pressing keys or buttons in other apps).
    var needsAccessibility: Bool {
        switch self {
        case .press, .type, .minimize, .fullscreen, .closeWindow: true
        default: false
        }
    }

    var question: String {
        switch self {
        case .quit(let app): "Quit \(app)?"
        case .closeTab: "Close this tab?"
        case .closeWindow: "Close this window?"
        case .press(let keys): "Press \(keys)?"
        case .type(let text): "Type \"\(text.prefix(40))\"?"
        default: "Do it?"
        }
    }
}

/// The duck's hands: opening, quitting and hiding apps, music, volume, tabs, shortcuts and typing.
/// No cursor: it uses AppleScript, NSWorkspace and Accessibility, like a keyboard wizard would.
enum Paws {
    // MARK: Understanding commands without AI

    /// Plain commands like "quit spotify", "next song", "volume 30", "close tab", "remind me in 10 minutes to stretch".
    static func parse(_ said: String) -> [Deed]? {
        var text = said.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for polite in ["please ", "can you ", "could you ", "hey duck ", "duck, ", "quackie, ", "would you "] {
            if text.hasPrefix(polite) { text.removeFirst(polite.count) }
        }
        func after(_ prefixes: [String]) -> String? {
            for prefix in prefixes where text.hasPrefix(prefix + " ") {
                let rest = text.dropFirst(prefix.count + 1).trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? nil : rest
            }
            return nil
        }

        switch text {
        case "play", "resume", "play music", "afspil", "spil musik": return [.play(nil)]
        case "pause", "stop the music", "pause music", "stop music", "shut up", "stop", "sluk musikken": return [.pause]
        case "next", "next song", "skip", "skip song", "skip this", "næste", "næste sang": return [.next]
        case "previous", "previous song", "go back a song", "last song", "forrige", "forrige sang": return [.previous]
        case "louder", "volume up", "turn it up", "skru op": return [.louder]
        case "quieter", "volume down", "turn it down", "skru ned": return [.quieter]
        case "mute", "unmute": return [.mute]
        case "close tab", "close this tab", "close the tab", "luk fanen": return [.closeTab]
        case "new tab", "ny fane": return [.newTab]
        case "reload", "refresh", "reload the page", "opdater": return [.reload]
        case "close window", "close this window", "luk vinduet": return [.closeWindow]
        case "minimize", "minimise", "minimize this", "minimer": return [.minimize]
        case "fullscreen", "full screen", "go fullscreen": return [.fullscreen]
        case "dark mode": return [.darkMode(true)]
        case "light mode": return [.darkMode(false)]
        case "toggle dark mode", "switch dark mode": return [.darkMode(nil)]
        case "dance", "dance for me", "dans": return [.dance]
        case "sleep", "go to sleep", "take a nap", "nap", "sov": return [.nap]
        default: break
        }

        if let number = text.firstMatch(of: /(?:set )?(?:the )?volume (?:to )?(\d{1,3})%?/) {
            return [.volume(min(100, Int(number.1) ?? 50))]
        }
        if let reminder = text.firstMatch(of: /remind me in (\d+) ?(seconds?|secs?|minutes?|mins?|hours?|h|m)(?: to| about)? (.+)/) {
            let amount = Int(reminder.1) ?? 5
            let unit = reminder.2
            let minutes = unit.hasPrefix("h") ? amount * 60 : unit.hasPrefix("s") ? max(1, amount / 60) : amount
            return [.remind(minutes: minutes, about: String(reminder.3))]
        }
        if let query = after(["search for", "search", "google", "look up", "søg efter", "søg på"]) { return [.search(query)] }
        if let thing = after(["open", "launch", "start", "åbn", "start op"]) {
            return looksLikeWebsite(thing) ? [.website(thing)] : [.open(appName(thing))]
        }
        if let thing = after(["go to", "visit", "gå til"]), looksLikeWebsite(thing) { return [.website(thing)] }
        if let app = after(["quit", "kill", "close the app", "close app", "force close", "shoot", "exit", "luk"]) {
            return [.quit(appName(app))]
        }
        if let app = after(["hide", "skjul"]) { return [.hide(appName(app))] }
        if let app = after(["switch to", "show me", "bring up", "skift til"]) { return [.focus(appName(app))] }
        if let song = after(["play", "afspil", "spil"]) { return [.play(song)] }
        if let keys = after(["press", "tryk på", "tryk"]) { return [.press(keys)] }
        if let words = after(["type", "skriv"]) { return [.type(words)] }
        return nil
    }

    private static func looksLikeWebsite(_ text: String) -> Bool {
        !text.contains(" ") && (text.contains(".") || text.hasPrefix("http"))
    }

    /// "spotify" → "Spotify", "the music app" → "Music".
    private static func appName(_ text: String) -> String {
        var name = text
        for filler in ["the ", "app ", " app", "this ", "my "] { name = name.replacingOccurrences(of: filler, with: " ") }
        name = name.trimmingCharacters(in: .whitespaces)
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.activationPolicy == .regular && ($0.localizedName?.lowercased().hasPrefix(name) ?? false)
        }), let real = running.localizedName { return real }
        if let url = findApp(name) { return url.deletingPathExtension().lastPathComponent }
        return name.capitalized
    }

    // MARK: Doing it

    struct Outcome {
        var moment: Moment
        var fill: [String: String] = [:]
        var failure: String?
    }

    static func perform(_ deed: Deed) async -> Outcome {
        if deed.needsAccessibility, !Hands.canPressButtons {
            return Outcome(moment: .cantDoThat, failure: "I need Accessibility for that. Settings → Hands → Allow.")
        }
        switch deed {
        case .open(let name):
            return await openApp(name)
        case .quit(let name):
            guard let app = running(name) else { return Outcome(moment: .cantDoThat, failure: "\(name) isn't running.") }
            let shown = app.localizedName ?? name
            return app.terminate() ? Outcome(moment: .quitApp, fill: ["app": shown]) : Outcome(moment: .cantDoThat)
        case .hide(let name):
            guard let app = running(name) else { return Outcome(moment: .cantDoThat, failure: "\(name) isn't running.") }
            app.hide()
            return Outcome(moment: .hidApp, fill: ["app": app.localizedName ?? name])
        case .focus(let name):
            if let app = running(name) {
                app.activate()
                return Outcome(moment: .didIt)
            }
            return await openApp(name)
        case .play(let song):
            return await music(song.map { "play \($0)" } ?? "play")
        case .pause: return await music("pause")
        case .next: return await music("next track")
        case .previous: return await music("previous track")
        case .volume(let level):
            _ = await AppleScript.run("set volume output volume \(level) without output muted")
            return Outcome(moment: .didIt)
        case .louder, .quieter:
            let change = deed == .louder ? 15 : -15
            _ = await AppleScript.run("set volume output volume ((output volume of (get volume settings)) + \(change)) without output muted")
            return Outcome(moment: .didIt)
        case .mute:
            _ = await AppleScript.run("set volume output muted (not (output muted of (get volume settings)))")
            return Outcome(moment: .didIt)
        case .website(let address):
            var link = address
            if !link.contains("://") { link = "https://" + link }
            guard let url = URL(string: link) else { return Outcome(moment: .cantDoThat) }
            NSWorkspace.shared.open(url)
            return Outcome(moment: .didIt)
        case .search(let query):
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            NSWorkspace.shared.open(components.url!)
            return Outcome(moment: .didIt)
        case .closeTab, .newTab, .reload:
            return await browser(deed)
        case .closeWindow:
            return pressButton(kAXCloseButtonAttribute) ? Outcome(moment: .didIt) : Outcome(moment: .cantDoThat)
        case .minimize:
            return setFrontWindow(kAXMinimizedAttribute, true) ? Outcome(moment: .didIt) : Outcome(moment: .cantDoThat)
        case .fullscreen:
            return setFrontWindow("AXFullScreen", true) ? Outcome(moment: .didIt) : Outcome(moment: .cantDoThat)
        case .press(let keys):
            do {
                _ = try Keyboard.press(keys)
                return Outcome(moment: .didIt)
            } catch {
                return Outcome(moment: .cantDoThat, failure: "I don't know the key \"\(keys)\".")
            }
        case .type(let text):
            await Keyboard.type(text)
            return Outcome(moment: .didIt)
        case .darkMode(let on):
            let value = on.map { $0 ? "true" : "false" } ?? "not dark mode"
            let result = await AppleScript.run(
                "tell application \"System Events\" to tell appearance preferences to set dark mode to \(value)")
            return result == nil ? Outcome(moment: .cantDoThat, failure: "macOS didn't let me. Allow Quackie Chan to control System Events.")
                : Outcome(moment: .didIt)
        case .remind, .dance, .nap:
            return Outcome(moment: .didIt)  // the director handles these itself
        }
    }

    // MARK: Apps

    static func running(_ name: String) -> NSRunningApplication? {
        let wanted = name.lowercased()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        return apps.first { $0.localizedName?.lowercased() == wanted }
            ?? apps.first { $0.localizedName?.lowercased().hasPrefix(wanted) ?? false }
            ?? apps.first { $0.localizedName?.lowercased().contains(wanted) ?? false }
    }

    private static func openApp(_ name: String) async -> Outcome {
        if let app = running(name) {
            app.activate()
            return Outcome(moment: .openedApp, fill: ["app": app.localizedName ?? name])
        }
        guard let url = findApp(name.lowercased()) else {
            return Outcome(moment: .cantDoThat, failure: "I couldn't find an app called \(name).")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return Outcome(moment: .openedApp, fill: ["app": url.deletingPathExtension().lastPathComponent])
    }

    static func findApp(_ wanted: String) -> URL? {
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                       NSHomeDirectory() + "/Applications", "/System/Library/CoreServices"]
        var apps: [URL] = []
        for folder in folders {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for item in items where item.hasSuffix(".app") {
                apps.append(URL(fileURLWithPath: folder).appendingPathComponent(item))
            }
        }
        func name(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent.lowercased() }
        return apps.first { name($0) == wanted } ?? apps.first { name($0).hasPrefix(wanted) } ?? apps.first { name($0).contains(wanted) }
    }

    // MARK: Music

    /// Sends a command to whichever player is running (Spotify first), or opens Music to play.
    private static func music(_ command: String) async -> Outcome {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let player = running.contains("com.spotify.client") ? "com.spotify.client" : "com.apple.Music"
        if command.hasPrefix("play "), command.count > 5 {
            let song = String(command.dropFirst(5)).replacingOccurrences(of: "\"", with: "")
            if player == "com.spotify.client" {
                NSWorkspace.shared.open(URL(string: "spotify:search:" + (song.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? song))!)
                return Outcome(moment: .musicControl)
            }
            let script = """
            tell application id "com.apple.Music"
                set found to (every track of playlist "Library" whose name contains "\(song)" or artist contains "\(song)")
                if found is {} then return "none"
                play item 1 of found
            end tell
            """
            let result = await AppleScript.run(script)
            return result?.stringValue == "none" ? Outcome(moment: .cantDoThat, failure: "I couldn't find \(song) in your Music library.")
                : Outcome(moment: .musicControl)
        }
        let result = await AppleScript.run("tell application id \"\(player)\" to \(command)")
        return result == nil ? Outcome(moment: .cantDoThat, failure: "Your music app didn't answer. Allow Quackie Chan to control it?")
            : Outcome(moment: .musicControl)
    }

    // MARK: Browser

    private static func browser(_ deed: Deed) async -> Outcome {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier, Browser.isBrowser(id) else {
            // Not a browser in front: the keyboard shortcut does the same thing.
            let keys = deed == .closeTab ? "cmd+w" : deed == .newTab ? "cmd+t" : "cmd+r"
            guard Hands.canPressButtons, (try? Keyboard.press(keys)) != nil else { return Outcome(moment: .cantDoThat) }
            return Outcome(moment: deed == .closeTab ? .closed : .didIt)
        }
        let safari = id.contains("Safari")
        let script: String = switch deed {
        case .closeTab: "close \(safari ? "current tab" : "active tab") of front window"
        case .newTab: safari ? "make new tab at end of tabs of front window" : "make new tab at end of tabs of front window"
        default: safari ? "set URL of current tab of front window to (URL of current tab of front window)" : "reload active tab of front window"
        }
        let result = await AppleScript.run("tell application id \"\(id)\" to \(script)")
        return result == nil ? Outcome(moment: .cantDoThat) : Outcome(moment: deed == .closeTab ? .closed : .didIt)
    }

    // MARK: Accessibility

    private static func frontWindow() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }
        return (window as! AXUIElement)
    }

    private static func pressButton(_ attribute: String) -> Bool {
        guard let window = frontWindow() else { return false }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &button) == .success, let button else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    private static func setFrontWindow(_ attribute: String, _ value: Bool) -> Bool {
        guard let window = frontWindow() else { return false }
        return AXUIElementSetAttributeValue(window, attribute as CFString, value as CFBoolean) == .success
    }
}

/// Pressing keys and typing, as if on a keyboard. Needs Accessibility.
enum Keyboard {
    private static let source = CGEventSource(stateID: .hidSystemState)

    static func type(_ text: String) async {
        for character in text {
            if character == "\n" {
                key(kVK_Return, flags: [])
            } else {
                let units = Array(String(character).utf16)
                for pressed in [true, false] {
                    guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: pressed) else { continue }
                    units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress) }
                    event.flags = []
                    event.post(tap: .cghidEventTap)
                }
            }
            try? await Task.sleep(for: .milliseconds(18))
        }
    }

    private static func key(_ code: Int, flags: CGEventFlags) {
        for pressed in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: pressed)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    struct UnknownKey: Error {}

    /// Presses a shortcut like "cmd+t", "return" or "cmd+shift+n". Returns a label like "⌘T".
    @discardableResult
    static func press(_ combo: String) throws -> String {
        var flags: CGEventFlags = []
        var label = ""
        var code: Int?
        let parts = combo.lowercased().replacingOccurrences(of: " ", with: "").split(whereSeparator: { $0 == "+" || $0 == "-" })
        for part in parts.map(String.init) {
            switch part {
            case "cmd", "command", "⌘": flags.insert(.maskCommand); label += "⌘"
            case "shift", "⇧": flags.insert(.maskShift); label += "⇧"
            case "option", "opt", "alt", "⌥": flags.insert(.maskAlternate); label += "⌥"
            case "ctrl", "control", "⌃": flags.insert(.maskControl); label += "⌃"
            default:
                guard let known = codes[part] else { throw UnknownKey() }
                code = known
                label += part.uppercased()
            }
        }
        guard let code else { throw UnknownKey() }
        key(code, flags: flags)
        return label
    }

    private static let codes: [String: Int] = {
        var map: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
            "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
            "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space, "delete": kVK_Delete,
            "backspace": kVK_Delete, "escape": kVK_Escape, "esc": kVK_Escape, "left": kVK_LeftArrow, "right": kVK_RightArrow,
            "up": kVK_UpArrow, "down": kVK_DownArrow, "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp,
            "pagedown": kVK_PageDown, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
        ]
        for (index, code) in [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12].enumerated() {
            map["f\(index + 1)"] = code
        }
        return map
    }()
}
