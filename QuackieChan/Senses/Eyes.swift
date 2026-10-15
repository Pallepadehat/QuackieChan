import AppKit
import ScreenCaptureKit
import Vision

/// One look at what you're doing.
struct Glance: Sendable {
    var appName: String
    var bundleID: String
    var pid: pid_t
    var windowTitle: String?
    var url: String?
    /// Text read off the front window, top to bottom.
    var text: String?
    /// A picture of the front window, for the AI brain. Never saved anywhere.
    var image: CGImage?
    /// A sharp close-up of what's around your pointer, when it's over the window. For "what's this?".
    var closeUp: CGImage?
    /// What your pointer is on: "button “Add to cart”", or the words under it.
    var pointing: String?
    /// Where your pointer is in the window, like "middle right".
    var pointerSpot: String?
    /// Text you've selected.
    var selection: String?
    /// Where typing goes right now, like "search field “Search Amazon”".
    var focus: String?
    /// The window's buttons, fields and links, by name.
    var controls: [String] = []

    var place: Place { Place.of(url: url, title: windowTitle, bundleID: bundleID) }

    /// The site's name, like "amazon.com".
    var site: String? {
        guard let url, let host = URL(string: url)?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The site's name for talking about it: "www.instagram.com" → "Instagram".
    var siteName: String? {
        guard let site else { return nil }
        let parts = site.split(separator: ".")
        let name = parts.count >= 2 ? parts[parts.count - 2] : parts.first ?? ""
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// What you're looking at, from the window title: "Amazon.com: Monkey Chair, Velvet" → "Monkey Chair, Velvet".
    var thing: String? {
        guard let title = windowTitle, !title.isEmpty else { return nil }
        let parts = title.components(separatedBy: CharacterSet(charactersIn: "|–—:")).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { part in
            !part.isEmpty && !(site.map { part.lowercased().contains($0.split(separator: ".").first ?? "") } ?? false)
        }
        guard let best = parts.max(by: { $0.count < $1.count }) else { return nil }
        return best.count > 40 ? String(best.prefix(38)) + "…" : best
    }

    /// Changes when you go somewhere else: another app or another page. (Not the window title: only the
    /// closer look can read that for most apps, and the key has to match between quick and close looks.)
    var key: String { [bundleID, url ?? ""].joined(separator: "|") }
}

/// How the duck sees: the front app, the browser's address, and (with permission) the front window's
/// pixels, read with on-device text recognition.
enum Eyes {
    static var canRecordScreen: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func askToRecordScreen() -> Bool { CGRequestScreenCaptureAccess() }

    static func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// The quick part: which app, and which page if it's a browser.
    static func quickLook() async -> Glance? {
        guard let app = frontApp(), let bundleID = app.bundleIdentifier else { return nil }
        var glance = Glance(appName: app.localizedName ?? bundleID, bundleID: bundleID, pid: app.processIdentifier)
        if let page = await Browser.currentPage(bundleID: bundleID) {
            glance.url = page.url
            glance.windowTitle = page.title
        }
        return glance
    }

    /// Everything the duck can see right now, for answering you: the front app and page, and (if seeing is on
    /// and allowed, and the app isn't on the never-look list) a sharp picture, every word on it laid out the way
    /// it is on screen, a close-up of what you're pointing at, and what Accessibility says the controls are.
    @MainActor
    static func lookNow() async -> Glance? {
        let prefs = Settings.shared.prefs
        guard var glance = await quickLook(), !prefs.ignoredApps.contains(glance.bundleID) else { return nil }
        if prefs.canSee, canRecordScreen { await lookCloser(at: &glance, carefully: true) }
        return glance
    }

    /// The app you're using. If that's Quackie Chan itself (its settings, or you just clicked the duck), it's the
    /// app whose window is on top underneath, which is what you'd mean by "what do you see?".
    static func frontApp() -> NSRunningApplication? {
        let me = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != me { return app }
        guard let window = Desk.windows().first else { return nil }
        return NSRunningApplication(processIdentifier: window.pid)
    }

    /// The slow part: a picture of the front window and the text on it. Needs Screen Recording.
    /// `carefully` is for when you ask about it: Retina-sharp, every word read accurately, plus the close-up and
    /// the Accessibility details. Otherwise it's a quick look for the duck's own comments.
    static func lookCloser(at glance: inout Glance, carefully: Bool = false) async {
        guard canRecordScreen else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let windows = content.windows.filter {
                $0.owningApplication?.processID == glance.pid && $0.windowLayer == 0 && $0.frame.width > 200 && $0.frame.height > 150
            }
            guard let window = windows.first else { return }
            if glance.windowTitle == nil { glance.windowTitle = window.title }
            let configuration = SCStreamConfiguration()
            // Careful looks capture at up to twice the window's size (Retina), so small print stays readable.
            let longest = max(window.frame.width, window.frame.height)
            let scale = carefully ? min(2, 3200 / longest) : min(1, 1280 / window.frame.width)
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
            glance.image = image
            // Prices need careful reading; everywhere else a quick read is plenty, unless you asked.
            glance.text = await read(image, carefully: carefully || glance.place == .shop)
            if carefully {
                await feel(window.frame, image: image, scale: scale, into: &glance)
            }
        } catch {
            // No picture this time; the duck still has the app and address.
        }
    }

    /// What Accessibility and your pointer add: the control you're pointing at, a close-up around it, your
    /// selection, where typing goes, and the window's named controls. `frame` is the window in Quartz points.
    private static func feel(_ frame: CGRect, image: CGImage, scale: CGFloat, into glance: inout Glance) async {
        let pointer = Feel.pointer
        if frame.contains(pointer) {
            let x = (pointer.x - frame.minX) / frame.width, y = (pointer.y - frame.minY) / frame.height
            glance.pointerSpot = (y < 0.33 ? "top" : y < 0.66 ? "middle" : "bottom") + " " + (x < 0.33 ? "left" : x < 0.66 ? "centre" : "right")
            // A close-up 900 × 560 points around the pointer, at full sharpness.
            let size = CGSize(width: min(900, frame.width), height: min(560, frame.height))
            var crop = CGRect(x: pointer.x - frame.minX - size.width / 2, y: pointer.y - frame.minY - size.height / 2,
                              width: size.width, height: size.height)
            crop.origin.x = min(max(0, crop.minX), frame.width - size.width)
            crop.origin.y = min(max(0, crop.minY), frame.height - size.height)
            let pixels = CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)
            if size.width < frame.width * 0.8 || size.height < frame.height * 0.8 {
                glance.closeUp = image.cropping(to: pixels.integral)
            }
            let control = await Task.detached(priority: .userInitiated) { Feel.control(at: pointer) }.value
            if let control, control.frame.width < frame.width * 0.9 {
                glance.pointing = "\(control.role) “\(control.label)”"
            }
        }
        let pid = glance.pid
        let details = await Task.detached(priority: .userInitiated) { () -> (String?, String?, [String]) in
            let field = Feel.focusedField()
            let focus = field.secure ? "a password field" : field.label.map { "“\($0)”" }
            let controls = Feel.controls(of: pid).map { $0.label.isEmpty ? $0.role : "\($0.role) “\($0.label)”" }
            return (Feel.selectedText(), focus, controls)
        }.value
        glance.selection = details.0
        glance.focus = details.1
        glance.controls = details.2
    }

    /// Reads the text in an image on the device, laid out like the screen: top to bottom, and words on the same
    /// row kept together left to right, with a gap marker between columns. Tables and prices stay readable.
    nonisolated static func read(_ image: CGImage, carefully: Bool) async -> String? {
        await Task.detached(priority: carefully ? .userInitiated : .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = carefully ? .accurate : .fast
            request.usesLanguageCorrection = carefully
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            let boxes = (request.results ?? []).compactMap { observation -> (box: CGRect, text: String)? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return (observation.boundingBox, text)
            }
            let text = layout(boxes)
            return text.isEmpty ? nil : String(text.prefix(carefully ? 7000 : 4000))
        }.value
    }

    /// Puts recognised text back in rows: boxes (Vision's normalised, y up) whose middles line up share a row.
    nonisolated static func layout(_ boxes: [(box: CGRect, text: String)]) -> String {
        let sorted = boxes.sorted { $0.box.midY > $1.box.midY }
        var rows: [[(box: CGRect, text: String)]] = []
        for item in sorted {
            if let last = rows.last?.first, abs(last.box.midY - item.box.midY) < max(last.box.height, item.box.height) * 0.5 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { row in
            let ordered = row.sorted { $0.box.minX < $1.box.minX }
            var line = ""
            var end: CGFloat?
            for item in ordered {
                if let end { line += item.box.minX - end > 0.04 ? "  |  " : " " }
                line += item.text
                end = item.box.maxX
            }
            return line
        }.joined(separator: "\n")
    }
}

/// Asks browsers for the address and title of the front tab with AppleScript. macOS asks you once per browser.
enum Browser {
    private static let chromium = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium",
    ]
    private static let safari = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]

    static func isBrowser(_ bundleID: String) -> Bool { chromium.contains(bundleID) || safari.contains(bundleID) }

    static func currentPage(bundleID: String) async -> (url: String, title: String)? {
        let source: String
        if safari.contains(bundleID) {
            source = "tell application id \"\(bundleID)\" to return {URL of front document, name of front document}"
        } else if chromium.contains(bundleID) {
            source = "tell application id \"\(bundleID)\" to return {URL of active tab of front window, title of active tab of front window}"
        } else {
            return nil
        }
        guard let result = await AppleScript.run(source), result.numberOfItems == 2,
              let url = result.atIndex(1)?.stringValue, let title = result.atIndex(2)?.stringValue
        else { return nil }
        return (url, title)
    }

    /// Closes the front tab, but only if it's still the page the duck is upset about.
    static func closeTab(bundleID: String, url: String) async -> Bool {
        guard let page = await currentPage(bundleID: bundleID), page.url == url else { return false }
        let tab = safari.contains(bundleID) ? "current tab" : "active tab"
        return await AppleScript.run("tell application id \"\(bundleID)\" to close \(tab) of front window") != nil
    }
}

/// Runs AppleScript off the main thread. NSAppleScript isn't thread safe, so every script runs on one queue.
enum AppleScript {
    private static let queue = DispatchQueue(label: "quackiechan.applescript")

    static func run(_ source: String) async -> NSAppleEventDescriptor? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? result : nil)
            }
        }
    }
}
