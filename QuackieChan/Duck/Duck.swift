import Observation
import SwiftUI

/// What the duck looks like and says right now. It turns what the duck is doing (and how it feels) into a pose
/// many times a second; the window controller moves it around and the director decides what it says.
@MainActor
@Observable
final class Duck {
    enum Activity: Equatable {
        case idle, walking, dragged, flying, soaring, sleeping, typing, aiming, celebrating, dizzy, petted, sulking
        /// Music: a head bob, then proper dancing, then completely losing it.
        case vibing, dancing, bananas
        /// Pecking at a window's tab bar until the tab closes.
        case pecking
        /// Listening to you talk.
        case listening
    }

    struct Bubble: Equatable, Identifiable {
        struct Choice: Equatable, Identifiable {
            let id = UUID()
            let title: String
            let action: @MainActor () -> Void
            static func == (a: Choice, b: Choice) -> Bool { a.id == b.id }
        }

        let id = UUID()
        var text: String
        var alarm = false
        /// Seconds left on the gun countdown, shown big in the bubble.
        var countdown: Int?
        /// Buttons under the text, like "I need it" or "Yes, quit it".
        var choices: [Choice] = []
    }

    struct Particle: Identifiable, Equatable {
        enum Kind: Equatable { case zzz, heart, anger, sweat, exclaim, question, tap, fire, smoke, bang, sparkle, note, impact, puff }
        let id = UUID()
        let kind: Kind
        /// Where it starts, in art pixels on the duck's canvas.
        let at: CGPoint
        /// Which way it drifts, in points.
        let drift: CGSize
    }

    /// The smooth part of the animation, worked out every frame: how high it bounces, how it squashes and
    /// stretches, and how far it leans. Poses swap like sprite frames; this moves in between.
    struct Motion: Equatable {
        /// Off the ground, in art pixels.
        var lift: CGFloat = 0
        /// Height scale: below 1 squashed, above 1 stretched. Width does the opposite.
        var squash: CGFloat = 1
        /// Lean in degrees, positive to the right.
        var tilt: Double = 0

        static let rest = Motion()
    }

    private(set) var pose = Pose()
    private(set) var motion = Motion.rest
    private(set) var activity = Activity.idle
    var facingLeft = false
    private(set) var bubble: Bubble?
    private(set) var particles: [Particle] = []
    /// Where the mouse is relative to the duck's head, in points (y up), for its eyes to follow.
    @ObservationIgnored var mouse: CGPoint = .zero
    /// The user is typing furiously.
    @ObservationIgnored var frantic = false
    /// Seconds per beat of whatever's playing.
    @ObservationIgnored var beat: TimeInterval = 0.5
    @ObservationIgnored var mood = Feelings.Mood.content

    /// Called when a line starts, so the duck's voice can babble along.
    @ObservationIgnored var onSay: ((String) -> Void)?

    @ObservationIgnored private var clock: TimeInterval = 0
    @ObservationIgnored private var activitySince: TimeInterval = 0
    @ObservationIgnored private var talkingUntil: TimeInterval = 0
    @ObservationIgnored private var nextBlink: TimeInterval = 3
    @ObservationIgnored private var blinkUntil: TimeInterval = 0
    @ObservationIgnored private var flashUntil: TimeInterval = 0
    @ObservationIgnored private var hopStart: TimeInterval = -10
    @ObservationIgnored private var yawnUntil: TimeInterval = 0
    @ObservationIgnored private var glanceUntil: TimeInterval = 0
    @ObservationIgnored private var glance = 0
    @ObservationIgnored private var bubbleTimer: Task<Void, Never>?
    @ObservationIgnored private var lastParticle: TimeInterval = 0
    @ObservationIgnored private var lastBeat = -1

    var isBusy: Bool { [.aiming, .dragged, .flying, .soaring, .pecking, .listening].contains(activity) }
    var isDancing: Bool { [.vibing, .dancing, .bananas].contains(activity) }
    var isFree: Bool { [.idle, .walking, .petted, .sulking].contains(activity) }

    // MARK: Doing things

    func set(_ activity: Activity) {
        guard activity != self.activity else { return }
        if [.aiming, .typing, .pecking].contains(activity) { facingLeft = false }
        if self.activity == .sleeping, activity != .sleeping { spawn(.exclaim) }
        self.activity = activity
        activitySince = clock
        lastBeat = -1
        // Whatever it was doing, it does now, not on the next tick.
        step(by: 0)
    }

    /// Shows a speech bubble and flaps the beak. The bubble goes away by itself, slower for longer lines.
    func say(_ text: String, alarm: Bool = false, countdown: Int? = nil, choices: [Bubble.Choice] = [], hold: TimeInterval? = nil) {
        if activity == .sleeping { set(.idle) }
        bubble = Bubble(text: text, alarm: alarm, countdown: countdown, choices: choices)
        talkingUntil = clock + min(2.4, 0.4 + Double(text.count) * 0.035)
        onSay?(text)
        bubbleTimer?.cancel()
        let seconds = hold ?? (choices.isEmpty ? min(12, 3.5 + Double(text.count) * 0.06) : 20)
        bubbleTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hush()
        }
    }

    func hush() {
        bubbleTimer?.cancel()
        bubble = nil
    }

    func updateCountdown(_ seconds: Int) {
        bubble?.countdown = seconds
        talkingUntil = clock + 0.3
        hop()
    }

    func quack() {
        talkingUntil = clock + 0.3
        hop()
        spawn(.note)
    }

    func hop() { hopStart = clock }

    /// Beats since the dancing started, counting smoothly, so moving and posing stay on the same beat.
    var beatPhase: Double { isDancing ? (clock - activitySince) / beat : 0 }

    var isInMotion: Bool { motion != .rest }

    func yawn() {
        yawnUntil = clock + 1.4
        spawn(.puff)
    }

    /// Fires the gun: a muzzle flash, a kick back, a BANG and some smoke.
    func bang() {
        flashUntil = clock + 0.18
        spawn(.bang, at: DuckArt.muzzle)
        spawn(.smoke, at: DuckArt.muzzle)
        hop()
    }

    func spawn(_ kind: Particle.Kind, at point: CGPoint? = nil) {
        let at = point ?? CGPoint(x: DuckArt.headTop.x + .random(in: -4...4), y: DuckArt.headTop.y)
        let drift = CGSize(width: .random(in: -14...14), height: kind == .smoke ? -36 : -30)
        let particle = Particle(kind: kind, at: at, drift: drift)
        particles.append(particle)
        if particles.count > 12 { particles.removeFirst() }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            self?.particles.removeAll { $0.id == particle.id }
        }
    }

    // MARK: Animation

    /// The bounce, squash and lean for this moment. Dances bounce on every beat and squash as they land.
    private func moving(_ t: TimeInterval) -> Motion {
        var motion = Motion.rest
        let phase = t / beat
        // |sin| peaks mid-beat and touches the ground on the beat itself.
        let bounce = CGFloat(abs(sin(.pi * phase)))
        let landing = CGFloat(max(0, cos(2 * .pi * phase)))  // 1 on the beat, when the feet hit the ground
        switch activity {
        case .vibing:
            motion.lift = 0.6 * bounce
            motion.squash = 1 - 0.035 * landing
            motion.tilt = 3 * sin(.pi * phase / 2)
        case .dancing:
            motion.lift = 3.5 * bounce
            motion.squash = 1 - 0.08 * landing + 0.04 * bounce
            motion.tilt = 7 * sin(.pi * phase)
        case .bananas:
            motion.lift = 6 * bounce
            motion.squash = 1 - 0.13 * landing + 0.07 * bounce
            motion.tilt = 12 * sin(.pi * phase)
        case .walking:
            // A waddle: rock side to side, a little bob each step.
            let step = t / 0.28
            motion.tilt = 4 * sin(2 * .pi * step)
            motion.lift = 0.7 * CGFloat(abs(sin(2 * .pi * step)))
        case .celebrating:
            let jump = t / 0.42
            motion.lift = 4 * CGFloat(abs(sin(.pi * jump)))
            motion.squash = 1 - 0.07 * CGFloat(max(0, cos(2 * .pi * jump)))
        case .petted:
            motion.tilt = 5 * sin(t * 2.2)
            motion.squash = 1 - 0.03 * CGFloat(abs(sin(t * 4.4)))
        case .dizzy:
            motion.tilt = 9 * sin(t * 7)
        case .soaring, .flying, .dragged:
            motion.tilt = 6 * sin(t * 14)
            motion.squash = 1 + 0.04 * CGFloat(sin(t * 28))
        case .typing:
            motion.squash = 1 - (frantic ? 0.03 : 0.015) * CGFloat(abs(sin(t * (frantic ? 40 : 20))))
        case .aiming:
            if clock < flashUntil + 0.12 { motion.tilt = -8 }  // the kick
        case .listening:
            motion.tilt = 3 * sin(t * 1.6)
        default:
            break
        }
        // A hop is a little arc with a squash on take-off and landing.
        let hop = (clock - hopStart) / 0.32
        if hop >= 0 && hop < 1 {
            motion.lift += 4 * CGFloat(sin(.pi * hop))
            motion.squash *= hop < 0.15 || hop > 0.85 ? 0.93 : 1.04
        }
        // Rounded so the view only updates when something visibly changes.
        motion.lift = (motion.lift * 4).rounded() / 4
        motion.squash = (motion.squash * 100).rounded() / 100
        motion.tilt = (motion.tilt * 2).rounded() / 2
        return motion
    }

    /// Runs `work` once each time a new beat starts.
    private func onEachBeat(_ t: TimeInterval, _ work: (Int) -> Void) {
        let count = Int(t / beat)
        if count != lastBeat {
            lastBeat = count
            work(count)
        }
    }

    /// The face it pulls when nothing in particular is happening, from how it feels.
    private var restingEyes: Pose.Eyes {
        switch mood {
        case .grumpy: .angry
        case .sleepy: .sleepy
        case .bored: Int(clock / 4) % 4 == 0 ? .sleepy : .open
        case .hyped, .loving: Int(clock / 3) % 3 == 0 ? .happy : .open
        default: .open
        }
    }

    /// Advances the animation and works out this moment's pose.
    func step(by seconds: TimeInterval) {
        clock += seconds
        let t = clock - activitySince
        var next = Pose()

        if clock > nextBlink {
            blinkUntil = clock + 0.13
            nextBlink = clock + .random(in: 2.2...6)
        }
        let talking = clock < talkingUntil && Int(clock * 8) % 2 == 0

        // Eyes follow the mouse, and now and then glance about on their own.
        let lookX = facingLeft ? -mouse.x : mouse.x
        next.lookX = abs(lookX) < 30 ? 0 : (lookX > 0 ? 1 : -1)
        next.lookY = abs(mouse.y) < 40 ? 0 : (mouse.y > 0 ? -1 : 1)
        if clock > glanceUntil + 4, Int.random(in: 0..<200) == 0 { glanceUntil = clock + 0.8; glance = [-1, 1].randomElement()! }
        if clock < glanceUntil { next.lookX = glance }
        next.bodyY = Int(clock / 1.1) % 2  // breathing

        switch activity {
        case .idle, .walking:
            next.eyes = restingEyes
            if activity == .walking {
                let phase = Int(t / 0.14) % 4
                next.legs = phase < 2 ? .stepA : .stepB
                next.bodyY = phase % 2
                next.headX = phase < 2 ? 0 : 1
            }
            if clock < blinkUntil { next.eyes = .blink }
        case .dragged, .flying:
            next.legs = .dangling
            next.eyes = .shocked
            next.beakOpen = true
            next.wing = Int(t / 0.09) % 2 == 0 ? .up : .rest
            next.bodyY = 0
        case .soaring:
            // Flying on purpose: wings flapping, feet tucked, looking where it's going.
            next.legs = .tucked
            next.wing = Int(t / 0.11) % 2 == 0 ? .up : .rest
            next.eyes = mood == .grumpy ? .angry : .open
            next.lookX = 1
            next.bodyY = 0
        case .sleeping:
            next.eyes = .blink
            next.legs = .tucked
            next.bodyY = 3 + Int(clock / 1.8) % 2
            next.headY = 1
            if clock - lastParticle > 1.6 { lastParticle = clock; spawn(.zzz) }
        case .typing:
            next.laptop = true
            next.legs = .tucked
            next.bodyY = 3
            next.lookY = 1
            next.lookX = 1
            let speed = frantic ? 0.05 : 0.1
            next.wing = Int(t / speed) % 2 == 0 ? .typingA : .typingB
            next.sweat = frantic
            if frantic { next.eyes = .angry }
            if clock - lastParticle > (frantic ? 0.35 : 0.9) {
                lastParticle = clock
                spawn(frantic ? .fire : .tap, at: CGPoint(x: 42 + .random(in: -4...4), y: 50))
            }
        case .aiming:
            next.gun = true
            next.wing = .forward
            next.eyes = .angry
            next.lookX = 1
            next.lookY = 0
            next.muzzleFlash = clock < flashUntil
            if next.muzzleFlash { next.headX = -1 }
        case .celebrating:
            next.eyes = .happy
            next.wing = Int(t / 0.12) % 2 == 0 ? .up : .rest
            next.legs = Int(t / 0.2) % 2 == 0 ? .stepA : .stepB
            next.blush = true
        case .dizzy:
            next.eyes = .dizzy
            next.headX = Int(t / 0.2) % 2 == 0 ? -1 : 1
            next.headY = 1
            if clock - lastParticle > 0.5 { lastParticle = clock; spawn(.sparkle) }
        case .petted:
            next.eyes = .happy
            next.blush = true
            next.headY = 1
            if clock - lastParticle > 0.8 { lastParticle = clock; spawn(.heart) }
        case .sulking:
            // Back turned, as huffy as a duck can be.
            next.eyes = mood == .sleepy ? .sleepy : .angry
            next.headY = 1
            next.lookX = -1
            if clock - lastParticle > 2.5 { lastParticle = clock; spawn(.anger) }
        case .listening:
            next.eyes = clock < blinkUntil ? .blink : .open
            next.headX = 1
            next.headY = Int(t / 0.9) % 2  // little nods
            next.lookX = 0
            if clock - lastParticle > 1.2 { lastParticle = clock; spawn(.question) }
        case .vibing:
            // Eyes shut, head bobbing on the beat, leaning into it.
            let half = t.truncatingRemainder(dividingBy: beat) < beat / 2
            next.eyes = .happy
            next.headY = half ? 2 : 0
            next.headX = (Int(t / beat) / 2) % 2 == 0 ? 1 : 0
            next.bodyY = half ? 1 : 0
            next.wing = Int(t / beat) % 4 == 3 && half ? .up : .rest
            onEachBeat(t) { count in if count % 2 == 0 { spawn(.note) } }
        case .dancing:
            // An eight-count: step-touch, step-touch, wing pumps, then a spin.
            let count = Int(t / beat) % 8
            let half = t.truncatingRemainder(dividingBy: beat) < beat / 2
            next.eyes = .happy
            next.beakOpen = half && count % 2 == 0
            next.headY = half ? 1 : 0
            switch count {
            case 0, 1, 2, 3:
                next.legs = count % 2 == 0 ? .stepA : .stepB
                next.wing = count % 2 == 0 ? .up : .forward
                next.headX = count % 2 == 0 ? 1 : -1
            case 4, 5:
                next.wing = half ? .up : .rest
                next.legs = .stepA
            default:
                next.wing = .up
                next.legs = .stepB
            }
            onEachBeat(t) { count in spawn(count % 4 == 0 ? .sparkle : .note) }
        case .bananas:
            let count = Int(t / beat)
            let half = t.truncatingRemainder(dividingBy: beat) < beat / 2
            next.eyes = .happy
            next.dealWithIt = true
            next.fingers = true
            next.pump = count % 2 == 0 ? 1 : 2
            next.beakOpen = half
            next.headY = half ? 2 : 0
            next.headX = half ? 1 : -1
            next.bodyY = half ? 1 : 0
            next.legs = count % 2 == 0 ? .stepA : .stepB
            onEachBeat(t) { _ in spawn([.note, .fire, .sparkle, .note].randomElement()!) }
        case .pecking:
            let down = Int(t / 0.16) % 2 == 0
            next.eyes = .angry
            next.headX = down ? 3 : 1
            next.headY = down ? 6 : 2
            next.beakOpen = !down
            next.legs = .stand
            if down && clock - lastParticle > 0.3 {
                lastParticle = clock
                spawn(.impact, at: CGPoint(x: 42, y: 40))
            }
        }
        if clock < yawnUntil, activity == .idle || activity == .sulking {
            next.beakOpen = true
            next.eyes = .blink
            next.headY = -1
        }
        // Dances turn around exactly once, on the beat, when the lean is back at zero, so the turn is seamless.
        // (Setting this every frame instead of toggling is what keeps it from spinning.)
        switch activity {
        case .dancing:
            let count = Int(t / beat) % 8
            facingLeft = count == 6 || count == 7
        case .bananas:
            facingLeft = (Int(t / beat) / 4) % 2 == 1
        default:
            break
        }
        if talking { next.beakOpen = true }
        if pose != next { pose = next }
        let nextMotion = moving(t)
        if nextMotion != motion { motion = nextMotion }
    }
}
