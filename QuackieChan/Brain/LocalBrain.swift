import CoreImage
import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon
@preconcurrency import MLXVLM
@preconcurrency import Tokenizers

/// One MLX model on the Mac's GPU. It loads when first needed and lets go of its memory when it's been idle a while.
actor LocalBrain {
    private var container: ModelContainer?
    private var loadedFolder: URL?
    private var loadedModel: BrainModel?
    private var lastUsed = Date()

    func load(_ model: BrainModel) async throws {
        let folder = ModelLibrary.folder(for: model)
        if loadedFolder == folder, container != nil { return }
        unload()
        Memory.cacheLimit = 64 * 1024 * 1024
        let configuration = ModelConfiguration(directory: folder)
        switch model.kind {
        case .vision:
            container = try await VLMModelFactory.shared.loadContainer(
                from: NoDownloads(), using: TokenizerFiles(), configuration: configuration)
        case .chat:
            container = try await LLMModelFactory.shared.loadContainer(
                from: NoDownloads(), using: TokenizerFiles(), configuration: configuration)
        }
        loadedFolder = folder
        loadedModel = model
    }

    func unload() {
        container = nil
        loadedFolder = nil
        loadedModel = nil
        Memory.clearCache()
    }

    /// Unloads if nothing has asked for a while, so the duck stays light.
    func unloadIfIdle(after seconds: TimeInterval) {
        if container != nil, Date().timeIntervalSince(lastUsed) > seconds { unload() }
    }

    /// Writes a reply to `prompt`, looking at `images` if there are any and the model can see. The first picture
    /// is the main one; a second is a close-up.
    func write(instructions: String, prompt: String, images: [CGImage], maxTokens: Int) async throws -> String {
        guard let container else { throw CocoaError(.featureUnsupported) }
        lastUsed = Date()
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.9, topP: 0.95)
        // Qwen3 thinks out loud unless told not to; the duck should just talk.
        // No resize here: the session's default squashes pictures into a 512 × 512 square first, which makes a
        // wide screen unreadable. Each model's own processor sizes the picture properly, keeping its shape, up to
        // the model's pixel budget (bigger than the processor's default, so small text stays readable).
        let session = ChatSession(container, instructions: instructions, generateParameters: parameters,
                                  processing: .init(resize: nil, maxPixels: loadedModel?.pixels),
                                  additionalContext: ["enable_thinking": false])
        let pictures = images.map { image -> UserInput.Image in
            let picture = CIImage(cgImage: image)
            let scale = min(1, 1920 / max(picture.extent.width, picture.extent.height))
            return .ciImage(picture.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        }
        let reply = try await session.respond(to: prompt, images: pictures, videos: [], audios: [])
        lastUsed = Date()
        return Self.withoutThinking(reply)
    }

    static func withoutThinking(_ reply: String) -> String {
        var text = reply
        while let start = text.range(of: "<think>") {
            let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex)?.upperBound ?? text.endIndex
            text.removeSubrange(start.lowerBound..<end)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The model is always loaded from its folder; nothing is fetched at load time.
private struct NoDownloads: Downloader {
    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        throw CocoaError(.fileNoSuchFile)
    }
}

/// Loads the tokenizer from the model's folder with swift-transformers.
private struct TokenizerFiles: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
