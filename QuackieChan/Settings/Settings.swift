import Foundation
import Observation

/// Everything you can set, saved as one JSON blob in UserDefaults.
struct Prefs: Codable, Equatable {
    var skinID = DuckSkin.standard.id
    var duckName = "Quackie Chan"
    var userName = ""
    var personality = Personality.sassy
    var size = DuckSize.medium
    var wander = true
    var sounds = true
    /// Dance when Spotify or Music is playing.
    var dance = true
    /// After a while of good music: sunglasses, middle fingers, chaos.
    var goBananas = true

    var goals: [Goal] = [.saveMoney]
    /// Things you told the duck in your own words, like "I'm learning Spanish". The AI brain reads them.
    var wishes: [String] = []
    var spendLimit = 100
    var bedtimeHour = 23
    var doomscrollMinutes = 15
    var chattiness = Chattiness.normal

    /// Let the duck look at the front window (Screen Recording) and read it on the device.
    var canSee = false
    /// What the duck looks at your screen with: a Hugging Face model, Apple Intelligence (`appleBrainID`),
    /// or nil to use only its built-in rules.
    var brainModelID: String?
    /// What you talk to the duck with. Nil uses the seeing brain.
    var chatModelID: String?
    /// Whether it makes a sound when it talks. Separate from sound effects (the gun, clicks, quacks).
    var voiceOn = true
    /// The sound it makes while it talks.
    var voice = Voice.quacks
    /// Set once the real recorded quack became the default voice, so older settings switch over once.
    var hasRealQuack = false
    /// ⌃⌥Q opens the talk box and listens.
    var talkShortcut = true
    /// Things you asked the duck to remember, for every conversation.
    var memories: [String] = []
    /// Double-clicking the duck opens the talk box. Off by default: it makes single clicks wait a moment.
    var doubleClickToTalk = false
    /// Let the duck do things on the Mac when you ask: open, quit and hide apps, music, volume, tabs, shortcuts.
    var hands = false
    /// Ask before quitting apps, closing things, pressing keys or typing.
    var askFirst = true
    var keepBrainLoaded = false
    /// What happens when the gun countdown runs out.
    var enforcement = Enforcement.threaten
    var ignoredApps: [String] = Prefs.privateApps

    var paused = false
    var hidden = false
    var hasMet = false

    static let privateApps = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.apple.systempreferences",
    ]

    var skin: DuckSkin { DuckSkin.with(id: skinID) }
}

enum DuckSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    /// Points per art pixel.
    var pixel: CGFloat {
        switch self {
        case .small: 2
        case .medium: 3
        case .large: 4
        }
    }
}

/// How the duck sounds when it talks. All synthesised, like animals in a video game.
nonisolated enum Voice: String, Codable, CaseIterable, Identifiable, Sendable {
    case quacks, gibberish, chirps, mumble, robot, off

    var id: String { rawValue }

    var name: String {
        switch self {
        case .gibberish: "Gibberish"
        case .quacks: "Quacks"
        case .chirps: "Chirps"
        case .mumble: "Mumble"
        case .robot: "Robot"
        case .off: "Silent"
        }
    }

    var detail: String {
        switch self {
        case .gibberish: "Blippy video game babble."
        case .quacks: "A real quack for every word. Very duck."
        case .chirps: "Bright, birdy chirps."
        case .mumble: "Low, cosy mumbling, like a tiny Sim."
        case .robot: "Beep boop. A duck from the future."
        case .off: "Just the speech bubble."
        }
    }
}

enum Enforcement: String, Codable, CaseIterable, Identifiable {
    case threaten, hide, close

    var id: String { rawValue }

    var name: String {
        switch self {
        case .threaten: "Nothing, it's an empty threat (BANG!)"
        case .hide: "Hide the app"
        case .close: "Peck the tab or window closed"
        }
    }
}

enum Chattiness: String, Codable, CaseIterable, Identifiable {
    case quiet, normal, chaos

    var id: String { rawValue }

    var name: String {
        switch self {
        case .quiet: "Quiet: only when it matters"
        case .normal: "Normal"
        case .chaos: "Chaos goblin"
        }
    }

    /// The shortest gap between unprompted comments.
    var commentGap: TimeInterval {
        switch self {
        case .quiet: 15 * 60
        case .normal: 4 * 60
        case .chaos: 60
        }
    }
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    var prefs: Prefs {
        didSet { if prefs != oldValue { save() } }
    }

    private static let key = "prefs"

    private init() {
        prefs = Self.load()
        if prefs.voice == .off {
            prefs.voiceOn = false
            prefs.voice = .quacks
        }
        if !prefs.hasRealQuack {
            prefs.hasRealQuack = true
            prefs.voice = .quacks
        }
    }

    /// Reads the saved settings over the defaults, so settings added in later versions get their default.
    private static func load() -> Prefs {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Prefs())) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: defaults.merging(saved) { $1 }),
              let prefs = try? JSONDecoder().decode(Prefs.self, from: merged)
        else { return Prefs() }
        return prefs
    }

    private func save() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Takes something you told the duck, turns on any goals it mentions, and remembers it.
    /// Returns the goals that were newly switched on.
    @discardableResult
    func tell(_ text: String) -> [Goal] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let found = Goal.mentioned(in: trimmed).filter { !prefs.goals.contains($0) }
        prefs.goals += found
        if !prefs.wishes.contains(trimmed) { prefs.wishes.append(trimmed) }
        return found
    }
}
