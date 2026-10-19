import AppKit
import CoreAudio
import CoreMediaIO

/// Whether you're on a call: a camera is on (in any app), or a meeting app is running while the microphone is in
/// use. Only on/off is asked of the camera and microphone; nothing is seen or heard, and no permission is needed.
nonisolated enum Meetings {
    /// Apps you have calls in.
    static let apps: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark",
        "com.apple.FaceTime", "com.skype.skype", "com.hnc.Discord", "com.tinyspeck.slackmacgap", "com.whereby.app",
    ]

    /// `listening` is the duck listening to you itself, which uses the microphone too.
    static func onACall(listening: Bool) async -> Bool {
        if cameraOn { return true }
        guard !listening, microphoneOn else { return false }
        return await MainActor.run {
            NSWorkspace.shared.runningApplications.contains { apps.contains($0.bundleIdentifier ?? "") }
        }
    }

    /// Some app has a camera running.
    static var cameraOn: Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }
        address.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        return devices.contains { device in
            var running: UInt32 = 0
            var used: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == noErr
                && running != 0
        }
    }

    /// Some app is recording from the default microphone.
    static var microphoneOn: Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }
}
