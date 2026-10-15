import AppKit
import CoreAudio

/// What's playing in Spotify or Music, if anything. Only asks apps that are already running, so checking
/// never opens them.
enum Music {
    struct Song: Equatable, Sendable {
        let title: String
        let artist: String
        /// Beats per minute, when the app knows (Music sometimes does; Spotify doesn't say).
        let bpm: Double?
    }

    private static let players = [
        ("com.spotify.client", false),
        ("com.apple.Music", true),
    ]

    /// Whether anything is coming out of the speakers at all. Cheap, so the music apps only get asked when it is.
    static var soundIsPlaying: Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return true }
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return true }
        return running != 0
    }

    /// Music sites, for when you listen in the browser.
    private static let webPlayers = ["music.apple.com", "music.youtube.com", "open.spotify.com", "soundcloud.com",
                                     "tidal.com", "deezer.com", "bandcamp.com"]

    static func nowPlaying() async -> Song? {
        guard soundIsPlaying else { return nil }
        if let song = await appPlaying() { return song }
        // A music site in the front browser tab, while sound is playing.
        if let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, Browser.isBrowser(app),
           let page = await Browser.currentPage(bundleID: app),
           let host = URL(string: page.url)?.host(), webPlayers.contains(where: host.hasSuffix) {
            let title = page.title.components(separatedBy: " - ").first ?? page.title
            return Song(title: title, artist: "", bpm: nil)
        }
        return nil
    }

    private static func appPlaying() async -> Song? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for (bundleID, knowsBPM) in players where running.contains(bundleID) {
            let bpm = knowsBPM ? ", bpm of current track" : ""
            let source = """
            tell application id "\(bundleID)"
                if player state is playing then return {name of current track, artist of current track\(bpm)}
            end tell
            """
            guard let result = await AppleScript.run(source), result.numberOfItems >= 2,
                  let title = result.atIndex(1)?.stringValue else { continue }
            let tempo = result.numberOfItems > 2 ? Double(result.atIndex(3)?.int32Value ?? 0) : 0
            return Song(title: title, artist: result.atIndex(2)?.stringValue ?? "", bpm: tempo > 40 ? tempo : nil)
        }
        return nil
    }
}

/// How the duck closes things, when you've allowed it: browser tabs with AppleScript, other windows by
/// pressing their close button with Accessibility. It never quits apps; unsaved work still asks to be saved.
enum Hands {
    static var canPressButtons: Bool { AXIsProcessTrusted() }

    static func askForAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// Closes whatever the glance was about: its tab, or its app's front window. Falls back to hiding the app.
    static func close(_ glance: Glance) async {
        if Browser.isBrowser(glance.bundleID), let url = glance.url {
            if await Browser.closeTab(bundleID: glance.bundleID, url: url) { return }
        } else if canPressButtons, pressClose(pid: glance.pid) {
            return
        }
        NSRunningApplication(processIdentifier: glance.pid)?.hide()
    }

    private static func pressClose(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return false }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }
}
