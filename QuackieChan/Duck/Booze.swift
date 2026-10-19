import Foundation
import Observation

/// Something you can hand the duck.
enum Treat {
    case bread, coffee, beer
}

/// How much the duck has had to drink. Left too long without a pet, it cracks open a beer; left longer, another,
/// and another. Pets, bread, coffee and a good nap sober it up again. It only drinks while you're at the Mac, so
/// it doesn't come back from a weekend completely gone.
@MainActor
@Observable
final class Booze {
    static let shared = Booze()

    enum Stage: Int, Comparable {
        case sober, tipsy, drunk, wasted

        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }

        var name: String {
            switch self {
            case .sober: "Sober"
            case .tipsy: "Tipsy"
            case .drunk: "Drunk"
            case .wasted: "Completely wasted"
            }
        }
    }

    /// The most it'll drink. Past this it just lies there and judges.
    static let most = 9

    private(set) var beers: Int
    /// A beer is due; it'll drink it as soon as it's free.
    @ObservationIgnored private(set) var thirsty = false
    /// Seconds you've been at the Mac without petting it.
    @ObservationIgnored private var neglect: TimeInterval
    @ObservationIgnored private var sleptOff: TimeInterval = 0
    @ObservationIgnored private var unsaved: TimeInterval = 0

    var stage: Stage { Self.stage(for: beers) }

    nonisolated static func stage(for beers: Int) -> Stage {
        switch beers {
        case ...0: .sober
        case 1...2: .tipsy
        case 3...5: .drunk
        default: .wasted
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        beers = min(Self.most, max(0, defaults.integer(forKey: "booze.beers")))
        neglect = defaults.double(forKey: "booze.neglect")
    }

    /// Time passing. Only counts toward the next beer while you're around.
    func pass(_ seconds: TimeInterval, youreAround: Bool, pace: Drinking) {
        guard let minutes = pace.minutes else {
            thirsty = false
            return
        }
        if youreAround { neglect += seconds }
        if beers < Self.most, neglect >= (beers == 0 ? minutes.first : minutes.then) * 60 { thirsty = true }
        unsaved += seconds
        if unsaved > 30 { save() }
    }

    func drank() {
        beers = min(Self.most, beers + 1)
        neglect = 0
        thirsty = false
        save()
    }

    /// A pet takes the edge off, unless it's too far gone to notice.
    func petted() {
        neglect = 0
        thirsty = false
        if stage < .wasted, beers > 0 { beers -= 1 }
        save()
    }

    func soberUp(by count: Int) {
        beers = max(0, beers - count)
        neglect = 0
        thirsty = false
        save()
    }

    /// Sleeping it off: a beer every four minutes.
    func sleep(_ seconds: TimeInterval) {
        guard beers > 0 else { return }
        sleptOff += seconds
        if sleptOff > 240 {
            sleptOff = 0
            beers -= 1
            save()
        }
    }

    private func save() {
        unsaved = 0
        UserDefaults.standard.set(beers, forKey: "booze.beers")
        UserDefaults.standard.set(neglect, forKey: "booze.neglect")
    }
}
