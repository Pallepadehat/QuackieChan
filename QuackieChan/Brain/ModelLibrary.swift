import Foundation
import Observation
@preconcurrency import HuggingFace

/// A model the duck can think with, from Hugging Face, run with MLX. Vision models can look at your screen
/// and chat; chat models only chat, but are smaller and quicker for it.
struct BrainModel: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case vision, chat }

    let id: String
    let kind: Kind
    let name: String
    let detail: String
    let bytes: Int64
    let license: String
    /// How much memory the Mac should have for it to run comfortably, in GB.
    var memory = 8
    /// A little label, like "Best eyes".
    var badge: String?
    /// The most picture it gets to look at, in pixels. Bigger reads small text better, but thinks slower.
    /// Nil leaves it to the model.
    var pixels: Int?
    /// The Hugging Face repo.
    var repo: String { id }

    var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    /// Whether this Mac has the memory for it.
    var fits: Bool { ProcessInfo.processInfo.physicalMemory >= UInt64(memory) * 1_000_000_000 }

    static let vision = [
        BrainModel(id: "mlx-community/LFM2.5-VL-1.6B-4bit", kind: .vision, name: "Quick Duck · LFM2.5-VL 1.6B",
                   detail: "Small and fast. Plenty for roasting your tabs.", bytes: 1_491_575_838, license: "LFM Open License"),
        BrainModel(id: "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit", kind: .vision, name: "Smart Duck · Qwen3-VL 4B",
                   detail: "Reads screens better and is funnier.", bytes: 3_093_767_519, license: "Apache 2.0",
                   memory: 16, pixels: 1_310_720),
        BrainModel(id: "mlx-community/Qwen3-VL-8B-Instruct-4bit", kind: .vision, name: "Eagle Duck · Qwen3-VL 8B",
                   detail: "Reads small print, menus and dense pages. Knows where everything is on screen.",
                   bytes: 5_760_665_246, license: "Apache 2.0", memory: 16, badge: "Sharp eyes", pixels: 1_800_000),
        BrainModel(id: "mlx-community/Qwen3.5-9B-4bit", kind: .vision, name: "Genius Duck · Qwen3.5 9B",
                   detail: "The best seer that fits most Macs. Sees and reasons about screens, and talks like a real person.",
                   bytes: 5_950_221_072, license: "Apache 2.0", memory: 16, badge: "Best eyes", pixels: 1_800_000),
        BrainModel(id: "mlx-community/Qwen3.6-35B-A3B-4bit", kind: .vision, name: "Big Brain Duck · Qwen3.6 35B-A3B",
                   detail: "Huge, but only wakes 3B at a time, so it's still quick. For Macs with lots of memory.",
                   bytes: 20_402_204_271, license: "Apache 2.0", memory: 32, badge: "Galaxy brain", pixels: 2_000_000),
        BrainModel(id: "mlx-community/gemma-4-e2b-it-4bit", kind: .vision, name: "Gemma Duck · Gemma 4 E2B",
                   detail: "Google's small multimodal model.", bytes: 3_600_000_000, license: "Gemma Terms"),
    ]

    static let chat = [
        BrainModel(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit", kind: .chat, name: "Chatty Duck · Qwen3 4B",
                   detail: "The best talker. Good at doing what you ask on your Mac.", bytes: 2_280_000_000, license: "Apache 2.0"),
        BrainModel(id: "mlx-community/Qwen3-1.7B-4bit", kind: .chat, name: "Pocket Duck · Qwen3 1.7B",
                   detail: "Tiny and quick. A bit dim, very charming.", bytes: 980_000_000, license: "Apache 2.0"),
        BrainModel(id: "mlx-community/gemma-3-1b-it-qat-4bit", kind: .chat, name: "Mini Duck · Gemma 3 1B",
                   detail: "The smallest. Says funny things, follows instructions loosely.", bytes: 770_000_000, license: "Gemma Terms"),
    ]

    static let all = vision + chat
    static let recommended = vision[0]

    static func with(id: String?) -> BrainModel? { all.first { $0.id == id } }
}

/// Picks the special "Apple Intelligence" brain instead of a downloaded one.
let appleBrainID = "apple-intelligence"

/// Which models are downloaded, and downloading and deleting them.
/// Everything lives in ~/Library/Application Support/Quackie Chan/Models.
@MainActor
@Observable
final class ModelLibrary {
    static let shared = ModelLibrary()

    enum Status: Equatable {
        case notInstalled
        case downloading(Double)
        case installed
        case failed(String)
    }

    private(set) var statuses: [String: Status] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    nonisolated static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Quackie Chan/Models", isDirectory: true)

    nonisolated static func folder(for model: BrainModel) -> URL {
        root.appendingPathComponent(model.repo.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    /// Written once a model is fully downloaded, so a half-finished download never counts.
    nonisolated private static func readyMarker(for model: BrainModel) -> URL {
        folder(for: model).appendingPathComponent(".quackie-ready")
    }

    private init() {
        try? FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        refresh()
    }

    func status(of model: BrainModel) -> Status { statuses[model.id] ?? .notInstalled }

    func isInstalled(_ model: BrainModel) -> Bool { status(of: model) == .installed }

    func refresh() {
        for model in BrainModel.all where tasks[model.id] == nil {
            if FileManager.default.fileExists(atPath: Self.readyMarker(for: model).path), Self.isComplete(model) {
                statuses[model.id] = .installed
            } else if case .failed = status(of: model) {
                continue
            } else {
                statuses[model.id] = .notInstalled
            }
        }
    }

    func download(_ model: BrainModel, then done: @escaping @MainActor () -> Void = {}) {
        guard tasks[model.id] == nil else { return }
        statuses[model.id] = .downloading(0)
        tasks[model.id] = Task { [weak self] in
            do {
                try await Self.fetch(model) { fraction in
                    Task { @MainActor in self?.report(model, fraction) }
                }
                try Task.checkCancellation()
                guard Self.isComplete(model) else {
                    throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Some of the model's files are missing."])
                }
                FileManager.default.createFile(atPath: Self.readyMarker(for: model).path, contents: Data())
                self?.finish(model, .installed)
                done()
            } catch {
                self?.finish(model, Task.isCancelled || error is CancellationError ? .notInstalled : .failed(Self.describe(error)))
            }
        }
    }

    func cancel(_ model: BrainModel) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        statuses[model.id] = .notInstalled
        Task.detached { Self.removeFiles(of: model) }
    }

    func delete(_ model: BrainModel) {
        Self.removeFiles(of: model)
        refresh()
    }

    private func report(_ model: BrainModel, _ fraction: Double) {
        guard case .downloading(let current) = status(of: model), fraction - current >= 0.005 else { return }
        statuses[model.id] = .downloading(min(0.99, fraction))
    }

    private func finish(_ model: BrainModel, _ status: Status) {
        tasks[model.id] = nil
        statuses[model.id] = status
    }

    /// Downloads the repo's weights, configs and tokenizer, then keeps a plain copy in our own folder.
    nonisolated private static func fetch(_ model: BrainModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        let cache = hubCache(for: model)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let hub = HubClient(cache: HubCache(cacheDirectory: cache))
        let snapshot = try await hub.downloadSnapshot(
            of: Repo.ID(rawValue: model.repo)!,
            matching: ["*.safetensors", "*.json", "*.jinja", "*.txt", "*.model", "*.tiktoken"],
            progressHandler: { @MainActor update in progress(update.fractionCompleted) })
        try Task.checkCancellation()
        let destination = folder(for: model)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in try FileManager.default.contentsOfDirectory(at: snapshot, includingPropertiesForKeys: nil) {
            try FileManager.default.moveItem(at: file.resolvingSymlinksInPath(), to: destination.appendingPathComponent(file.lastPathComponent))
        }
        try? FileManager.default.removeItem(at: cache)
    }

    /// Each download gets its own cache, so deleting or cancelling one model never touches another's download.
    nonisolated private static func hubCache(for model: BrainModel) -> URL {
        root.appendingPathComponent(".hub-" + model.repo.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    /// Whether a model's folder has what it needs to load: its config, a tokenizer and its weights.
    nonisolated static func isComplete(_ model: BrainModel) -> Bool {
        let folder = folder(for: model)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.contains("config.json")
            && files.contains { $0 == "tokenizer.json" || $0 == "tokenizer.model" || $0 == "tokenizer_config.json" }
            && files.contains { $0.hasSuffix(".safetensors") }
    }

    nonisolated private static func removeFiles(of model: BrainModel) {
        try? FileManager.default.removeItem(at: folder(for: model))
        try? FileManager.default.removeItem(at: hubCache(for: model))
    }

    private static func describe(_ error: Error) -> String {
        let error = error as NSError
        if error.domain == NSURLErrorDomain { return "The download stopped: \(error.localizedDescription) Try again." }
        if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError { return "Your Mac ran out of space." }
        return "The download didn't finish: \(error.localizedDescription)"
    }
}
