import Testing
@testable import QuackieChan

struct PriceTests {
    @Test(arguments: [
        ("$8,000", 8000.0), ("8.000,00 kr.", 8000.0), ("€ 1 299", 1299.0), ("USD 49.99", 49.99),
        ("Only 1.299,95 DKK today", 1299.95), ("£12", 12.0),
    ])
    func findsPrices(text: String, expected: Double) {
        #expect(Prices.highest(in: text) == expected)
    }

    @Test func picksTheBiggestPrice() {
        #expect(Prices.highest(in: "Free shipping over $35\nMonkey Chair\n$8,000.00\nSave $200") == 8000)
    }

    @Test func ignoresTextWithoutPrices() {
        #expect(Prices.highest(in: "Version 2.5 released in 2026") == nil)
    }
}

struct GoalTests {
    @Test func findsGoalsInWhatYouSay() {
        #expect(Goal.mentioned(in: "I want to save money") == [.saveMoney])
        #expect(Goal.mentioned(in: "jeg vil gerne spare penge og sove mere").contains(.sleep))
        #expect(Goal.mentioned(in: "I'm learning to juggle").isEmpty)
    }

    @Test func knowsShopsAndSocialMedia() {
        #expect(Place.of(url: "https://www.amazon.com/monkey-chair/dp/123", title: nil, bundleID: nil) == .shop)
        #expect(Place.of(url: "https://www.reddit.com/r/all", title: nil, bundleID: nil) == .social)
        #expect(Place.of(url: "https://github.com", title: nil, bundleID: nil) == .other)
    }
}

struct ArtTests {
    @Test func everyDuckAndPosePaints() {
        let poses = [Pose(), Pose(eyes: .angry, gun: true, muzzleFlash: true), Pose(legs: .tucked, laptop: true),
                     Pose(eyes: .sad, dealWithIt: true, fingers: true, pump: 2), Pose(eyes: .sleepy, wing: .up),
                     Pose(eyes: .shocked, legs: .dangling, wing: .up), Pose(eyes: .blink, bodyY: 3, legs: .tucked)]
        for skin in DuckSkin.all {
            for pose in poses {
                let pixels = DuckArt.paint(skin, pose)
                #expect(pixels.count == DuckArt.canvasHeight)
                #expect(pixels.allSatisfy { $0.count == DuckArt.canvasWidth })
                // Every letter used has a colour.
                let palette = skin.plumage.palette
                #expect(pixels.joined().compactMap { $0 }.allSatisfy { palette[$0] != nil })
            }
        }
    }
}

@MainActor
struct BrainTests {
    @Test func readsTheModelsReply() {
        #expect(Minds.parse(#"Sure! {"mood": "threat", "line": "Drop the chair."}"#) == Take(mood: .threat, line: "Drop the chair."))
        #expect(Minds.parse("Nice spreadsheet, nerd.") == Take(mood: .tease, line: "Nice spreadsheet, nerd."))
        #expect(Minds.parse("") == nil)
    }

    @Test func readsWhatToDo() {
        let answer = Minds.parseAnswer(#"{"say": "Bye bye, Spotify.", "do": [{"action": "quit", "target": "Spotify"}, {"action": "volume", "level": 30}]}"#)
        #expect(answer.say == "Bye bye, Spotify.")
        #expect(answer.deeds == [.quit("Spotify"), .volume(30)])
        #expect(Minds.parseAnswer("Bread.").deeds.isEmpty)
    }

    @Test func readsPlainRepliesWithActions() {
        let answer = Minds.parseAnswer("Bye bye, Spotify. It had a good run.\nDO: quit Spotify\nDO: volume 30")
        #expect(answer.say == "Bye bye, Spotify. It had a good run.")
        #expect(answer.deeds.count == 2)
        #expect(answer.deeds.last == .volume(30))
    }

    @Test func survivesCutOffJSON() {
        let answer = Minds.parseAnswer(#"{"say": "You can't shoot me from Paseo, little doomster. I've got a green thumb, a cozy pond by my duckside"#)
        #expect(answer.say.hasPrefix("You can't shoot me from Paseo"))
        #expect(!answer.say.contains("{"))
    }

    @Test func keepsLinesShort() {
        let long = "First sentence here. " + String(repeating: "and on and on ", count: 30)
        #expect(Minds.shorten(long, to: 170) == "First sentence here.")
        #expect(Minds.shorten("Short.", to: 170) == "Short.")
    }

    @Test func dropsThinking() {
        #expect(LocalBrain.withoutThinking("<think>hmm</think> Quack!") == "Quack!")
    }
}

@MainActor
struct CommandTests {
    @Test func understandsPlainCommands() {
        #expect(Paws.parse("next song") == [.next])
        #expect(Paws.parse("Please pause") == [.pause])
        #expect(Paws.parse("volume 30") == [.volume(30)])
        #expect(Paws.parse("set the volume to 75%") == [.volume(75)])
        #expect(Paws.parse("close this tab") == [.closeTab])
        #expect(Paws.parse("open github.com") == [.website("github.com")])
        #expect(Paws.parse("search for duck facts") == [.search("duck facts")])
        #expect(Paws.parse("remind me in 10 minutes to stretch") == [.remind(minutes: 10, about: "stretch")])
        #expect(Paws.parse("press cmd+t") == [.press("cmd+t")])
    }

    @Test func leavesConversationToTheBrain() {
        #expect(Paws.parse("how are you feeling today?") == nil)
        #expect(Paws.parse("tell me a joke") == nil)
    }
}

@MainActor
struct LineTests {
    @Test func doesNotRepeatItselfStraightAway() {
        let lines = (0..<6).map { _ in Lines.pick(.poke, .sassy) }
        #expect(Set(lines).count == lines.count)
    }

    @Test func fillsInPlaceholders() {
        let line = Lines.pick(.batteryLow, .sassy, fill: ["percent": "9"])
        #expect(line.contains("9"))
        #expect(!line.contains("{"))
    }

    @Test func hasOpinionsAboutApps() {
        #expect(Lines.about(app: "Xcode", bundleID: "com.apple.dt.Xcode", .sassy) != nil)
        #expect(Lines.about(app: "Some Random App", bundleID: "com.example.random", .sassy) == nil)
    }
}

struct SoundTests {
    @Test func loadsTheRealQuackWithoutTheSilence() throws {
        let quack = try #require(Synth.recorded)
        let seconds = Double(quack.count) / Synth.rate
        #expect(seconds > 0.12 && seconds < 0.4)
        #expect((quack.map(abs).max() ?? 0) <= 0.81)
    }

    @Test func pitchesQuacksUpAndDown() throws {
        let quack = try #require(Synth.recorded)
        #expect(Synth.resample(quack, by: 1.25).count < quack.count)
        #expect(Synth.resample(quack, by: 0.8).count > quack.count)
    }
}
