import Foundation

/// The things the duck can hold you to without any AI: each comes with built-in rules.
nonisolated enum Goal: String, Codable, CaseIterable, Identifiable, Sendable {
    case saveMoney, stopDoomscrolling, focus, sleep, hydrate, takeBreaks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saveMoney: "Save money"
        case .stopDoomscrolling: "Stop doomscrolling"
        case .focus: "Stay focused"
        case .sleep: "Go to bed on time"
        case .hydrate: "Drink water"
        case .takeBreaks: "Take breaks"
        }
    }

    var emoji: String {
        switch self {
        case .saveMoney: "💸"
        case .stopDoomscrolling: "📵"
        case .focus: "🎯"
        case .sleep: "🛌"
        case .hydrate: "💧"
        case .takeBreaks: "🧘"
        }
    }

    var detail: String {
        switch self {
        case .saveMoney: "Pulls a gun when you look at something pricier than your limit on a shopping site."
        case .stopDoomscrolling: "Notices when you've been on social media too long. Then less patient."
        case .focus: "Glares when YouTube, Netflix or social media sneak in."
        case .sleep: "Nags you after bedtime."
        case .hydrate: "Reminds you to drink water every hour."
        case .takeBreaks: "Tells you to stand up after 50 minutes straight."
        }
    }

    /// Words that switch a goal on when you tell the duck something. English and a little Danish.
    private var keywords: [String] {
        switch self {
        case .saveMoney: ["money", "spend", "save", "budget", "broke", "shopping", "buy", "penge", "spare", "købe"]
        case .stopDoomscrolling: ["scroll", "tiktok", "instagram", "reddit", "twitter", "social media", "phone", "sociale medier"]
        case .focus: ["focus", "procrastinat", "productive", "distract", "study", "work", "fokus", "arbejd"]
        case .sleep: ["sleep", "bed", "late", "night", "tired", "søvn", "seng", "sove"]
        case .hydrate: ["water", "hydrat", "drink", "vand"]
        case .takeBreaks: ["break", "stretch", "posture", "stand up", "sitting", "pause", "strække"]
        }
    }

    static func mentioned(in text: String) -> [Goal] {
        let lowered = text.lowercased()
        return allCases.filter { goal in goal.keywords.contains { lowered.contains($0) } }
    }
}

/// What kind of place you're at, from the address, the window title and the app.
nonisolated enum Place: String, Sendable {
    case shop, social, video, other

    static func of(url: String?, title: String?, bundleID: String?) -> Place {
        let haystack = [url, title].compactMap { $0?.lowercased() }.joined(separator: " ")
        if shopSites.contains(where: haystack.contains) { return .shop }
        if socialSites.contains(where: haystack.contains) { return .social }
        if videoSites.contains(where: haystack.contains) || videoApps.contains(bundleID ?? "") { return .video }
        return .other
    }

    static let shopSites = [
        "amazon.", "ebay.", "etsy.", "aliexpress.", "temu.", "shein.", "zalando.", "asos.", "walmart.", "target.com",
        "bestbuy.", "ikea.", "wish.com", "alibaba.", "apple.com/shop", "myshopify.com", "wayfair.", "zara.com",
        "hm.com", "nike.com", "elgiganten.", "proshop.", "komplett.", "coolshop.", "bilka.", "boozt.",
        "/checkout", "/cart", "/basket", "/kurv",
    ]
    static let socialSites = [
        "twitter.com", "x.com/", "://x.com", "reddit.com", "tiktok.com", "instagram.com", "facebook.com",
        "threads.net", "bsky.app", "9gag.com", "youtube.com/shorts", "linkedin.com/feed", "tumblr.com",
    ]
    static let videoSites = ["youtube.com", "netflix.com", "twitch.tv", "disneyplus.com", "primevideo.com", "max.com", "viaplay."]
    static let videoApps = ["com.netflix.Netflix", "com.valvesoftware.steam", "com.apple.TV"]

    /// Words on a page that mean you're about to pay for something.
    static let checkoutWords = [
        "add to cart", "add to basket", "buy now", "proceed to checkout", "place order", "place your order",
        "add to bag", "complete purchase", "læg i kurv", "køb nu", "gå til kassen", "in den warenkorb", "jetzt kaufen",
    ]
}
