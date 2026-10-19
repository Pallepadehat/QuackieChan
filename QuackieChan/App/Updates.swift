import AppKit
import Sparkle

/// Keeps Quackie Chan up to date with Sparkle. Once a day it looks at the appcast on GitHub (one small download,
/// nothing about you is sent) and when there's a newer duck, your duck tells you about it itself. Sparkle then
/// downloads it, checks it's signed by the same developer and with our EdDSA key, swaps it in and relaunches.
@MainActor
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updates()

    /// Called with the new version when one is found on the daily check. Return true if the duck is telling you
    /// about it; false and Sparkle shows its own window.
    var onFound: ((String) -> Bool)?

    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)

    func start() {
        // Builds from Xcode stay as they are, rather than being swapped for the latest release.
        #if !DEBUG
        controller.startUpdater()
        #endif
    }

    var updater: SPUUpdater { controller.updater }

    /// Checks right now, with Sparkle's window.
    func checkNow() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    var checksAutomatically: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Lets the duck break the news instead of a window popping up out of nowhere.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Only for the background check: Sparkle's window comes up if the duck can't say it.
        let version = update.displayVersionString
        return MainActor.assumeIsolated { !(onFound?(version) ?? false) }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {}
}
