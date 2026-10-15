import AVFoundation
import AppKit

/// The macOS permissions the duck can use, and what to do about each: ask if macOS hasn't asked yet,
/// otherwise open the right page of System Settings (macOS only ever asks once).
enum Permission: CaseIterable, Identifiable {
    case microphone, screenRecording, accessibility

    var id: Self { self }

    enum State { case allowed, notAsked, denied }

    var state: State {
        switch self {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .allowed
            case .notDetermined: return .notAsked
            default: return .denied
            }
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .allowed : .notAsked
        case .accessibility:
            return AXIsProcessTrusted() ? .allowed : .notAsked
        }
    }

    private var settingsPage: String {
        switch self {
        case .microphone: "Privacy_Microphone"
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        }
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsPage)")!)
    }

    /// Asks macOS if it still will, otherwise opens System Settings where you can switch it on.
    @MainActor
    func request() async {
        // An app without a Dock icon has to come forward, or the system prompt can end up behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        switch self {
        case .microphone:
            if state == .notAsked {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else if state == .denied {
                openSettings()
            }
        case .screenRecording:
            // Returns false straight away if macOS asked before; then the switch is in System Settings.
            if !CGRequestScreenCaptureAccess() { openSettings() }
        case .accessibility:
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            if !AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) { openSettings() }
        }
    }
}

import SwiftUI

/// A settings row showing whether a permission is on, with a button that actually gets you there.
struct PermissionRow: View {
    let permission: Permission
    let title: String
    @State private var state: Permission.State = .notAsked

    var body: some View {
        LabeledContent(title) {
            switch state {
            case .allowed:
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .notAsked:
                Button("Allow…") { Task { await permission.request(); refresh() } }
            case .denied:
                HStack(spacing: 8) {
                    Text("Turned off").foregroundStyle(.secondary)
                    Button("Open System Settings…") { permission.openSettings() }
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func refresh() {
        let now = permission.state
        if now != state { state = now }
    }
}
