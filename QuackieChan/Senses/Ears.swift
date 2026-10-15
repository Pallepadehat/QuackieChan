import AVFoundation
import Speech

/// Turns what you say into text, on the Mac. Uses SpeechAnalyzer on macOS 26 and later, and the older
/// on-device SFSpeechRecognizer before that. Audio never leaves the Mac and is never saved.
@MainActor
final class Ears {
    /// Called with everything heard so far, as it changes.
    var onText: ((String) -> Void)?
    /// Called once you've stopped talking for a moment.
    var onPause: (() -> Void)?

    private let engine = AVAudioEngine()
    private var session: (any HearingSession)?
    private var silence: Task<Void, Never>?

    private(set) var isListening = false

    static var micAllowed: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    static func askForMic() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() async throws {
        guard !isListening else { return }
        if !Self.micAllowed {
            guard await Self.askForMic() else { throw EarsError.noMic }
        }
        let session: any HearingSession
        if #available(macOS 26, *) {
            session = try await AnalyzerSession()
        } else {
            session = try await RecognizerSession()
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            session.feed(buffer)
        }
        try await session.begin(inputFormat: format) { [weak self] text in
            Task { @MainActor in self?.heard(text) }
        }
        engine.prepare()
        try engine.start()
        self.session = session
        isListening = true
        waitForSilence(seconds: 6)  // give up if nothing is said at all
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        silence?.cancel()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        session?.end()
        session = nil
    }

    private func heard(_ text: String) {
        guard isListening else { return }
        onText?(text)
        waitForSilence(seconds: 1.6)
    }

    private func waitForSilence(seconds: Double) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.isListening else { return }
            self.stop()
            self.onPause?()
        }
    }

    enum EarsError: LocalizedError {
        case noMic, noRecognizer

        var errorDescription: String? {
            switch self {
            case .noMic: "The duck needs the microphone. Allow it in System Settings → Privacy & Security → Microphone."
            case .noRecognizer: "Speech recognition isn't available for your language on this Mac."
            }
        }
    }
}

/// One way of turning audio into text.
private protocol HearingSession: AnyObject, Sendable {
    func begin(inputFormat: AVAudioFormat, onText: @escaping @Sendable (String) -> Void) async throws
    func feed(_ buffer: AVAudioPCMBuffer)
    func end()
}

/// macOS 26's SpeechAnalyzer with a SpeechTranscriber: fast, private, and good at long speech.
@available(macOS 26, *)
private final class AnalyzerSession: HearingSession, @unchecked Sendable {
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var results: Task<Void, Never>?

    init() async throws {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale(identifier: "en-US")
        transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await install.downloadAndInstall()
        }
        analyzer = SpeechAnalyzer(modules: [transcriber])
        (input, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    }

    func begin(inputFormat: AVAudioFormat, onText: @escaping @Sendable (String) -> Void) async throws {
        targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        if let targetFormat, targetFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }
        let transcriber = transcriber
        results = Task {
            var settled = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        settled += text
                        onText(settled)
                    } else {
                        onText(settled + text)
                    }
                }
            } catch {}
        }
        try await analyzer.start(inputSequence: input)
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var consumed = false
        converter.convert(to: converted, error: nil) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    func end() {
        continuation.finish()
        let analyzer = analyzer
        Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
    }
}

/// Before macOS 26: SFSpeechRecognizer, kept on the device.
private final class RecognizerSession: HearingSession, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?

    init() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized, let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.supportsOnDeviceRecognition
        else { throw Ears.EarsError.noRecognizer }
        self.recognizer = recognizer
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
    }

    func begin(inputFormat: AVAudioFormat, onText: @escaping @Sendable (String) -> Void) async throws {
        task = recognizer.recognitionTask(with: request) { result, _ in
            if let result { onText(result.bestTranscription.formattedString) }
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }

    func end() {
        request.endAudio()
        task?.finish()
    }
}
