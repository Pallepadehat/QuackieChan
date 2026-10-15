import Foundation

/// What the duck knows for certain and answers instantly, without any AI: its name, your name, the time and
/// date, and the things you ask it to remember. These are the questions small models most often get wrong.
@MainActor
enum Knowing {
    static func reply(to said: String, settings: Settings) -> String? {
        let text = said.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let prefs = settings.prefs
        let personality = prefs.personality

        // Learning your name.
        if let name = text.firstMatch(of: /^(?:my name is|my name's|call me|i am called|i'm called|jeg hedder|kald mig) (.+)$/) {
            let raw = said.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            let original = String(raw.suffix(name.1.count))
            let clean = original.split(separator: " ").prefix(3).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            settings.prefs.userName = clean
            return flavour(personality, [
                .sassy: "\(clean). Fine. I'll remember it. Unlike your passwords.",
                .sergeant: "\(clean.uppercased()). NAME LOGGED, RECRUIT.",
                .wholesome: "\(clean)! What a lovely name. I'll never forget it 💛",
                .unhinged: "\(clean). I've carved it into my tiny duck heart. And the Dock.",
            ])
        }
        // Remembering things.
        if let fact = text.firstMatch(of: /^(?:remember that|remember|husk at|husk) (.+)$/), !text.hasPrefix("remember me") {
            let original = String(said.trimmingCharacters(in: .whitespacesAndNewlines).suffix(fact.1.count))
            if !settings.prefs.memories.contains(original) { settings.prefs.memories.append(original) }
            return flavour(personality, [
                .sassy: "Noted. Filed under things I'll bring up at the worst moment.",
                .sergeant: "COMMITTED TO MEMORY, RECRUIT.",
                .wholesome: "Got it! I'll remember that 💛",
                .unhinged: "It is written. In my brain. Which is mostly bread.",
            ])
        }
        if ["forget everything", "forget it all", "glem alt"].contains(text) {
            settings.prefs.memories.removeAll()
            Minds.shared.forgetConversation()
            return "Forgotten. Who are you? Kidding. But the rest is gone."
        }
        if ["what do you remember", "what do you know about me", "hvad husker du"].contains(where: text.hasPrefix) {
            let known = (prefs.userName.isEmpty ? [] : ["your name is \(prefs.userName)"]) + prefs.memories
            return known.isEmpty ? "Nothing yet. Tell me things! Say \"remember that…\"."
                : "I know " + known.prefix(4).joined(separator: ", ") + (known.count > 4 ? ", and more." : ".")
        }
        // Its own name.
        if ["what's your name", "whats your name", "what is your name", "who are you", "what are you called",
            "hvad hedder du", "hvem er du"].contains(where: text.hasPrefix) {
            return flavour(personality, [
                .sassy: "I'm \(prefs.duckName). The duck. On your screen. Judging you. Nice to meet you, I guess.",
                .sergeant: "\(prefs.duckName.uppercased()), RECRUIT. YOUR DESKTOP DRILL SERGEANT.",
                .wholesome: "I'm \(prefs.duckName)! Your little screen duck and biggest fan 💛",
                .unhinged: "I am \(prefs.duckName). Duck. Legend. Menace. Owner of one (1) tiny gun.",
            ])
        }
        // Your name.
        if ["what's my name", "whats my name", "what is my name", "who am i", "do you know my name", "hvad hedder jeg"].contains(where: text.hasPrefix) {
            return prefs.userName.isEmpty
                ? "I don't know yet! Tell me: \"my name is…\""
                : flavour(personality, [
                    .sassy: "You're \(prefs.userName). Obviously. I pay attention.",
                    .sergeant: "YOU ARE RECRUIT \(prefs.userName.uppercased())!",
                    .wholesome: "You're \(prefs.userName), my favourite person! 💛",
                    .unhinged: "\(prefs.userName). Unless you've been replaced. Have you been replaced?",
                ])
        }
        // Time and date.
        if ["what time is it", "what's the time", "whats the time", "hvad er klokken"].contains(where: text.hasPrefix) {
            return "It's \(Date().formatted(date: .omitted, time: .shortened)). " + (Calendar.current.component(.hour, from: Date()) >= 23
                ? "Which is bedtime, by the way." : "Time for bread.")
        }
        if ["what day is it", "what's the date", "whats the date", "what is the date", "what's today", "hvilken dag"].contains(where: text.hasPrefix) {
            return "It's \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))."
        }
        return nil
    }

    private static func flavour(_ personality: Personality, _ lines: [Personality: String]) -> String {
        lines[personality] ?? lines[.sassy] ?? "Quack."
    }
}
