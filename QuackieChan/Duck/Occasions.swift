import Foundation

/// A day of the year, without the year: your birthday.
nonisolated struct MonthDay: Codable, Equatable, Hashable, Sendable {
    var month: Int
    var day: Int

    func matches(_ date: Date, in calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return parts.month == month && parts.day == day
    }

    /// "5 March", "march 5th", "the 5th of March", "5. marts". Months by name, in English or Danish, so there's no
    /// guessing whether 03/05 is March or May.
    static func parse(_ text: String) -> MonthDay? {
        let months = [["jan", "januar"], ["feb", "februar"], ["mar", "marts"], ["apr", "april"], ["may", "maj"], ["jun", "juni"],
                      ["jul", "juli"], ["aug", "august"], ["sep", "september"], ["oct", "okt", "oktober"], ["nov", "november"],
                      ["dec", "dek", "december"]]
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard let month = words.lazy.compactMap({ word in months.firstIndex { $0.contains { word.hasPrefix($0) } } }).first,
              let day = words.lazy.compactMap({ Int($0.filter(\.isNumber)) }).first, (1...31).contains(day)
        else { return nil }
        return MonthDay(month: month + 1, day: day)
    }

    /// "5 March".
    var name: String {
        let names = DateFormatter().monthSymbols ?? []
        return "\(day) \(names.indices.contains(month - 1) ? names[month - 1] : "\(month)")"
    }
}

/// Days the duck dresses up for: a Santa hat all December, a pumpkin in Halloween week, and a party hat (and cake)
/// on your birthday, which wins over the rest.
nonisolated enum Occasion: String, Sendable {
    case birthday, christmas, halloween

    var hat: Hat {
        switch self {
        case .birthday: .party
        case .christmas: .santa
        case .halloween: .pumpkin
        }
    }

    static func on(_ date: Date, birthday: MonthDay?, calendar: Calendar = .current) -> Occasion? {
        if let birthday, birthday.matches(date, in: calendar) { return .birthday }
        let parts = calendar.dateComponents([.month, .day], from: date)
        switch (parts.month ?? 0, parts.day ?? 0) {
        case (12, _): return .christmas
        case (10, 24...31): return .halloween
        default: return nil
        }
    }

    /// What it says the first time it sees you on the day.
    var moment: Moment {
        switch self {
        case .birthday: .birthday
        case .christmas: .christmas
        case .halloween: .halloween
        }
    }
}

extension Prefs {
    /// Your duck, in its hat for the day if it's dressing up.
    var dressedSkin: DuckSkin {
        guard seasonal, let occasion = Occasion.on(Date(), birthday: birthday) else { return skin }
        return skin.wearing(occasion.hat)
    }
}
