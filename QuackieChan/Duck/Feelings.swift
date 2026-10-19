import Foundation
import Observation

/// How the duck feels. Everything that happens to it nudges these, they drift back over time, and together
/// they make its mood: the face it pulls when it's doing nothing, what it does on its own, and what it says.
@MainActor
@Observable
final class Feelings {
    static let shared = Feelings()

    /// All 0...1.
    private(set) var joy = 0.6
    private(set) var love = 0.5
    private(set) var anger = 0.0
    private(set) var energy = 0.8
    private(set) var boredom = 0.0

    enum Mood: String {
        case happy, loving, grumpy, sleepy, bored, hyped, content

        var emoji: String {
            switch self {
            case .happy: "😄"
            case .loving: "🥰"
            case .grumpy: "😤"
            case .sleepy: "😴"
            case .bored: "🥱"
            case .hyped: "🤩"
            case .content: "🙂"
            }
        }

        var name: String { rawValue.capitalized }
    }

    enum Event {
        case poked, pokedTooMuch, petted, grabbed, thrown, landedHard, flew
        case music, musicStopped, bananas
        case keptGoal, brokeGoal, firedGun, closedSomething
        case typedALot, userCameBack, userLeft
        case praised, insulted, chatted, helped
        case windowYanked
        case drank, fed, caffeinated
    }

    var mood: Mood {
        if anger > 0.55 { return .grumpy }
        if energy < 0.22 { return .sleepy }
        if joy > 0.8 && energy > 0.6 { return .hyped }
        if love > 0.75 { return .loving }
        if boredom > 0.65 { return .bored }
        if joy > 0.62 { return .happy }
        return .content
    }

    func feel(_ event: Event) {
        switch event {
        case .poked: anger += 0.05; boredom -= 0.2
        case .pokedTooMuch: anger += 0.3; love -= 0.05
        case .petted: love += 0.06; anger -= 0.08; joy += 0.03
        case .grabbed: anger += 0.04; boredom -= 0.3
        case .thrown: joy += 0.08; anger += 0.05; energy += 0.05; boredom = 0
        case .landedHard: anger += 0.12; energy -= 0.05
        case .flew: joy += 0.03; boredom -= 0.2
        case .music: joy += 0.04; energy += 0.04; boredom = 0
        case .musicStopped: joy -= 0.1
        case .bananas: joy += 0.15; energy += 0.1
        case .keptGoal: joy += 0.12; love += 0.08
        case .brokeGoal: anger += 0.15; joy -= 0.1
        case .firedGun: anger -= 0.25; joy += 0.05  // very therapeutic
        case .closedSomething: joy += 0.08
        case .typedALot: energy -= 0.02; boredom -= 0.1
        case .userCameBack: love += 0.08; boredom = 0; energy += 0.2
        case .userLeft: boredom += 0.2
        case .praised: joy += 0.15; love += 0.12; anger -= 0.1
        case .insulted: anger += 0.25; joy -= 0.1
        case .chatted: love += 0.04; boredom = 0
        case .helped: joy += 0.06; love += 0.03
        case .windowYanked: anger += 0.1
        case .drank: joy += 0.08; energy -= 0.06; anger -= 0.05
        case .fed: love += 0.1; joy += 0.1; boredom = 0
        case .caffeinated: energy = 1; joy += 0.05; boredom = 0
        }
        clamp()
    }

    /// Feelings fade toward the duck's resting state, boredom creeps up, and it gets sleepy at night.
    func drift(by seconds: TimeInterval) {
        let rate = seconds / 600
        anger -= anger * rate * 2
        joy += (0.6 - joy) * rate
        love += (0.5 - love) * rate * 0.5
        boredom += rate * 0.6
        let hour = Calendar.current.component(.hour, from: Date())
        let night = hour >= 23 || hour < 6
        energy += ((night ? 0.15 : 0.75) - energy) * rate * 0.7
        clamp()
    }

    private func clamp() {
        joy = min(1, max(0, joy))
        love = min(1, max(0, love))
        anger = min(1, max(0, anger))
        energy = min(1, max(0, energy))
        boredom = min(1, max(0, boredom))
    }
}
