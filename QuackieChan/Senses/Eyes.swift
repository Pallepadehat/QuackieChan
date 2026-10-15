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
    /// A small picture of the front window, for the AI brain. Never saved anywhere.
    var image: CGImage?

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
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        var glance = Glance(appName: app.localizedName ?? bundleID, bundleID: bundleID, pid: app.processIdentifier)
        if let page = await Browser.currentPage(bundleID: bundleID) {
            glance.url = page.url
            glance.windowTitle = page.title
        }
        return glance
    }

    /// The slow part: a picture of the front window and the text on it. Needs Screen Recording.
    static func lookCloser(at glance: inout Glance) async {
        guard canRecordScreen else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let windows = content.windows.filter {
                $0.owningApplication?.processID == glance.pid && $0.windowLayer == 0 && $0.frame.width > 200 && $0.frame.height > 150
            }
            guard let window = windows.first else { return }
            if glance.windowTitle == nil { glance.windowTitle = window.title }
            let configuration = SCStreamConfiguration()
            let scale = min(1, 1280 / window.frame.width)
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
            glance.image = image
            // Prices need careful reading; everywhere else a quick read is plenty.
            glance.text = await read(image, carefully: glance.place == .shop)
        } catch {
            // No picture this time; the duck still has the app and address.
        }
    }

    /// Reads the text in an image, top to bottom, on the device.
    nonisolated static func read(_ image: CGImage, carefully: Bool) async -> String? {
        await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = carefully ? .accurate : .fast
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: image).perform([request])
            let lines = (request.results ?? [])
                .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                .compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            return text.isEmpty ? nil : String(text.prefix(4000))
        }.value
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
