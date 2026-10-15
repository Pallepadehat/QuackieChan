import AVFoundation

/// Every sound the duck makes, synthesised in code: a gunshot that actually sounds like one, the gun being
/// cocked, quacks, and a babbling duck voice for when it talks. No audio files, so nothing to license.
/// The audio engine only runs while something is playing, so a quiet duck costs nothing.
@MainActor
final class Sounds {
    static let shared = Sounds()

    enum Effect: CaseIterable { case gunshot, cock, quack, tick, spared, pop, thud, whoosh }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var cache: [Effect: AVAudioPCMBuffer] = [:]
    private var stopTimer: Task<Void, Never>?

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ effect: Effect) {
        guard Settings.shared.prefs.sounds else { return }
        let buffer = cache[effect] ?? Synth.make(effect, format: format)
        cache[effect] = buffer
        schedule(buffer)
    }

    /// Says a line in the duck's voice (a sound per syllable or word), pitched to its personality.
    func babble(_ text: String, personality: Personality, voice: Voice? = nil) {
        let voice = voice ?? Settings.shared.prefs.voice
        guard Settings.shared.prefs.sounds, voice != .off else { return }
        player.stop()  // a new line cuts off the old one
        schedule(Synth.speak(text, voice: voice, personality: personality, format: format))
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(buffer, at: nil, options: [])
        if !player.isPlaying { player.play() }
        // Stop the engine a moment after the last sound so it doesn't sit there using CPU.
        stopTimer?.cancel()
        let length = Double(buffer.frameLength) / format.sampleRate
        stopTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(length + 1.5))
            guard !Task.isCancelled, let self else { return }
            self.player.stop()
            self.engine.stop()
        }
    }
}

/// Tiny sound synthesiser: noise, oscillators, envelopes and filters, written straight into buffers.
nonisolated enum Synth {
    static let rate = 44_100.0

    static func make(_ effect: Sounds.Effect, format: AVAudioFormat) -> AVAudioPCMBuffer {
        switch effect {
        case .gunshot: return buffer(gunshot(), format)
        case .cock: return buffer(cock(), format)
        case .quack: return buffer(quack(pitch: .random(in: 0.9...1.15)), format)
        case .tick: return buffer(tone(1650, length: 0.035, decay: 0.012, volume: 0.35), format)
        case .spared: return buffer(tone(784, length: 0.12, decay: 0.08, volume: 0.3) + tone(1175, length: 0.3, decay: 0.12, volume: 0.3), format)
        case .pop: return buffer(sweep(from: 900, to: 300, length: 0.07, volume: 0.4), format)
        case .thud: return buffer(sweep(from: 140, to: 50, length: 0.18, volume: 0.7), format)
        case .whoosh: return buffer(whoosh(), format)
        }
    }

    /// A pistol shot: a sharp crack, the body of the blast, a low thump, and the room ringing after.
    static func gunshot() -> [Float] {
        let count = Int(rate * 1.1)
        var out = [Float](repeating: 0, count: count)
        var body: Float = 0, room: Float = 0, roomLow: Float = 0
        for i in 0..<count {
            let t = Float(Double(i) / rate)
            let noise = Float.random(in: -1...1)
            let crack = noise * exp(-t / 0.006)
            body += 0.22 * (noise - body)  // one-pole low-pass
            room += 0.06 * (noise - room)
            roomLow += 0.02 * (room - roomLow)
            let frequency = 45 + 110 * exp(-t / 0.03)
            let thump = sin(2 * .pi * frequency * t) * exp(-t / 0.11)
            let sample = 1.0 * crack + 1.6 * body * exp(-t / 0.07) + 0.9 * thump + 1.8 * roomLow * exp(-t / 0.33)
            out[i] = tanh(sample * 1.8) * 0.9
        }
        return out
    }

    /// The slide racked back and forward: two metallic clicks.
    static func cock() -> [Float] {
        func click(_ volume: Float, ring: Float) -> [Float] {
            (0..<Int(rate * 0.06)).map { i in
                let t = Float(Double(i) / rate)
                let noise = Float.random(in: -1...1) * exp(-t / 0.004)
                return volume * (noise + 0.5 * sin(2 * .pi * ring * t) * exp(-t / 0.012))
            }
        }
        return click(0.5, ring: 2900) + silence(0.09) + click(0.8, ring: 2300) + silence(0.05)
    }

    /// A nasal quack: a buzzy sawtooth dropping in pitch, pushed through a bandpass "beak".
    static func quack(pitch: Float = 1) -> [Float] {
        let count = Int(rate * 0.2)
        var phase: Float = 0
        var raw = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Float(Double(i) / rate)
            let frequency = (430 - 160 * t / 0.2) * pitch
            phase += frequency / Float(rate)
            let saw = 2 * (phase - floor(phase)) - 1
            let envelope = min(1, t / 0.01) * exp(-t / 0.09)
            raw[i] = saw * envelope
        }
        return bandpass(raw, center: 1300 * pitch, q: 2.2).map { tanh($0 * 3) * 0.55 }
    }

    /// A line in one of the duck's voices: a sound per syllable (or per word, for quacks).
    static func speak(_ text: String, voice: Voice, personality: Personality, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let pitch: Float = switch personality {
        case .sergeant: 0.7
        case .wholesome: 1.35
        case .unhinged: 1.1
        case .sassy: 1
        }
        let letters = text.filter(\.isLetter).count
        let words = max(1, text.split(whereSeparator: { $0.isWhitespace }).count)
        let asking = text.hasSuffix("?")
        var out: [Float] = []
        switch voice {
        case .off:
            break
        case .gibberish:
            let syllables = max(2, min(16, letters / 3))
            for index in 0..<syllables {
                let rise: Float = asking && index == syllables - 1 ? 1.3 : 1
                out += blip(pitch: 330 * pitch * .random(in: 0.85...1.3) * rise, length: .random(in: 0.055...0.085),
                            vowel: [800, 1150, 1500, 2200, 950].randomElement()!, square: true) + silence(0.022)
            }
        case .quacks:
            for index in 0..<min(7, words) {
                let rise: Float = asking && index == min(7, words) - 1 ? 1.25 : 1
                out += quack(pitch: pitch * .random(in: 0.9...1.2) * rise).map { $0 * 0.8 } + silence(.random(in: 0.04...0.09))
            }
        case .chirps:
            let syllables = max(2, min(14, letters / 3))
            for _ in 0..<syllables {
                let base = 1800 * pitch * .random(in: 0.85...1.25)
                out += sweep(from: base, to: base * .random(in: 1.15...1.5), length: .random(in: 0.04...0.07), volume: 0.28)
                    + silence(.random(in: 0.02...0.05))
            }
        case .mumble:
            let syllables = max(2, min(10, letters / 4))
            for index in 0..<syllables {
                let rise: Float = asking && index == syllables - 1 ? 1.25 : 1
                out += blip(pitch: 150 * pitch * .random(in: 0.9...1.2) * rise, length: .random(in: 0.11...0.17),
                            vowel: [500, 700, 900].randomElement()!, square: false) + silence(0.03)
            }
        case .robot:
            let syllables = max(2, min(14, letters / 3))
            for _ in 0..<syllables {
                let note = [440, 523, 587, 659, 784].randomElement()! * pitch
                out += tone(note, length: 0.07, decay: 0.2, volume: 0.25).enumerated().map { index, sample in
                    // Ring modulation for that tin-can sound.
                    sample * (Float(index / 220 % 2 == 0 ? 1 : -1))
                } + silence(0.03)
            }
        }
        return buffer(out.isEmpty ? silence(0.01) : out, format)
    }

    /// A short voiced sound: a square or sawtooth at `pitch`, shaped by a vowel-ish band-pass.
    static func blip(pitch: Float, length: Double, vowel: Float, square: Bool) -> [Float] {
        var phase: Float = 0
        let raw = (0..<Int(rate * length)).map { i -> Float in
            let t = Float(Double(i) / rate)
            phase += pitch / Float(rate)
            let wave: Float = square ? (phase - floor(phase) < 0.5 ? 1 : -1) : 2 * (phase - floor(phase)) - 1
            let envelope = min(1, t / 0.008) * min(1, (Float(length) - t) / 0.02)
            return wave * envelope
        }
        return bandpass(raw, center: vowel, q: 1.6).map { $0 * 0.5 }
    }

    // MARK: Building blocks

    static func tone(_ frequency: Float, length: Double, decay: Float, volume: Float) -> [Float] {
        (0..<Int(rate * length)).map { i in
            let t = Float(Double(i) / rate)
            return volume * sin(2 * .pi * frequency * t) * exp(-t / decay)
        }
    }

    static func sweep(from start: Float, to end: Float, length: Double, volume: Float) -> [Float] {
        var phase: Float = 0
        let count = Int(rate * length)
        return (0..<count).map { i in
            let progress = Float(i) / Float(count)
            phase += (start + (end - start) * progress) / Float(rate)
            return volume * sin(2 * .pi * phase) * (1 - progress)
        }
    }

    static func whoosh() -> [Float] {
        let raw = (0..<Int(rate * 0.35)).map { i -> Float in
            let t = Float(Double(i) / rate)
            return Float.random(in: -1...1) * sin(.pi * t / 0.35) * 0.5
        }
        return bandpass(raw, center: 900, q: 0.8)
    }

    static func silence(_ length: Double) -> [Float] { [Float](repeating: 0, count: Int(rate * length)) }

    /// A biquad band-pass filter.
    static func bandpass(_ input: [Float], center: Float, q: Float) -> [Float] {
        let omega = 2 * Float.pi * center / Float(rate)
        let alpha = sin(omega) / (2 * q)
        let a0 = 1 + alpha
        let b0 = alpha / a0, b2 = -alpha / a0, a1 = -2 * cos(omega) / a0, a2 = (1 - alpha) / a0
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        return input.map { x in
            let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y * 2
        }
    }

    static func buffer(_ samples: [Float], _ format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
