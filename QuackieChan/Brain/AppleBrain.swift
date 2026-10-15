import CoreGraphics
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence's on-device model: nothing to download. Text on macOS 26, and on macOS 27 it can look
/// at pictures too, so it can be the duck's eyes as well as its mouth.
enum AppleBrain {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    static var canSee: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 27, *) {
            return SystemLanguageModel.default.isAvailable && SystemLanguageModel.default.capabilities.contains(.vision)
        }
        #endif
        return false
    }

    /// Why it can't be used, in words for the settings screen.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible): return "This Mac can't run Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings."
            case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready."
            case .unavailable: return "Apple Intelligence isn't available."
            }
        }
        #endif
        return "Needs macOS 26 or later."
    }

    static func write(instructions: String, prompt: String, image: CGImage?) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 27, *), let image, canSee {
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond {
                prompt
                Attachment(image)
            }.content
        }
        if #available(macOS 26, *) {
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond(to: prompt).content
        }
        #endif
        throw CocoaError(.featureUnsupported)
    }
}
