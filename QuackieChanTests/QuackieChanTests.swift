import CoreGraphics
import Foundation
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
                     Pose(eyes: .shocked, legs: .dangling, wing: .up), Pose(eyes: .blink, bodyY: 3, legs: .tucked),
                     Pose(eyes: .drunk, wing: .forward, beer: 2, flushed: true, monkHair: 1),
                     Pose(eyes: .angry, beakOpen: true, wing: .forward, muzzleFlash: true, flushed: true, monkHair: 2, machineGun: true),
                     Pose(wing: .forward, mug: true), Pose(wing: .forward, beer: 1), Pose(beakOpen: true, bread: true)]
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

    @Test func cansPaintInTheDucksColours() {
        let palette = Plumage.classic.palette
        for kind in 0..<CanArt.kinds {
            let rows = CanArt.rows(kind)
            #expect(Set(rows.map(\.count)).count == 1)
            #expect(rows.joined().allSatisfy { $0 == "." || palette[$0] != nil })
        }
    }

    @Test func occasionsAndPropsPaint() {
        var props = [Pose(), Pose(wing: .forward), Pose(legs: .tucked), Pose(beakOpen: true)]
        props[0].tie = true; props[0].onAir = true
        props[1].cake = true; props[1].horn = 2
        props[2].tomato = true; props[2].bodyY = -3
        props[3].horn = 1
        for hat in [Hat.santa, .pumpkin, .party] {
            for plumage in Plumage.allCases {
                let skin = DuckSkin(id: "test", name: "Test", plumage: plumage, hat: hat)
                for pose in props {
                    let pixels = DuckArt.paint(skin, pose)
                    #expect(pixels.count == DuckArt.canvasHeight)
                    #expect(pixels.joined().compactMap { $0 }.allSatisfy { skin.plumage.palette[$0] != nil })
                }
            }
        }
    }

    @Test func poopPaintsInTheDucksColours() {
        let palette = Plumage.classic.palette
        #expect(Set(PoopArt.rows.map(\.count)).count == 1)
        #expect(PoopArt.rows.joined().allSatisfy { $0 == "." || palette[$0] != nil })
    }

    @Test func monkHairKnocksTheHatOff() {
        let skin = DuckSkin.with(id: "merlin")
        let hatted = DuckArt.paint(skin, Pose()).joined().filter { $0 == "B" }.count
        let monk = DuckArt.paint(skin, Pose(monkHair: 1)).joined().filter { $0 == "B" }.count
        #expect(hatted > 0 && monk == 0)
    }
}

struct DrunkTests {
    @Test func getsWorseWithEveryBeer() {
        #expect(Booze.stage(for: 0) == .sober)
        #expect(Booze.stage(for: 2) == .tipsy)
        #expect(Booze.stage(for: 4) == .drunk)
        #expect(Booze.stage(for: 9) == .wasted)
    }

    @Test @MainActor func slursOnlyWhenProperlyDrunk() {
        #expect(Duck.slur("Yes sir", 1) == "Yes sir")
        #expect(Duck.slur("Yes sir", 2).hasPrefix("Yesh shir"))
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

    @Test func readsTricks() {
        #expect(Minds.parseAnswer("You asked for it. Pew.\nDO: shoot").deeds == [.shoot])
        #expect(Minds.parseAnswer("Watch this.\nDO: go bananas").deeds == [.bananas])
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

    @Test func knowsWhenYouAskAboutTheScreen() {
        #expect(Minds.asksAboutScreen("What do you see?"))
        #expect(Minds.asksAboutScreen("what do you think of this design"))
        #expect(!Minds.asksAboutScreen("tell me a joke"))
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
        #expect(Paws.parse("Can you pause the music for me please?") == [.pause])
        #expect(Paws.parse("next song please") == [.next])
        #expect(Paws.parse("Shoot me!") == [.shoot])
        #expect(Paws.parse("go bananas") == [.bananas])
        if case .quit = Paws.parse("shoot spotify")?.first {} else { Issue.record("\"shoot spotify\" should quit Spotify") }
    }

    @Test func sitsAndStaysAndGetsUp() {
        #expect(Paws.parse("Sit!") == [.sit])
        #expect(Paws.parse("sit down please") == [.sit])
        #expect(Paws.parse("stay") == [.sit])
        #expect(Paws.parse("sæt dig") == [.sit])
        #expect(Paws.parse("stand up") == [.stand])
        #expect(Paws.parse("have a coffee") == [.coffee])
        #expect(Paws.parse("have some bread") == [.bread])
        #expect(Minds.parseAnswer("Fine. Sitting.\nDO: sit").deeds == [.sit])
        #expect(Deed.sit.isTrick && Deed.beer.isTrick)
    }

    @Test func catchesObviousRequests() {
        #expect(Paws.obviousRequest(in: "Show me your best dance moves") == [.dance])
        #expect(Paws.obviousRequest(in: "I dare you to shoot me") == [.shoot])
        #expect(Paws.obviousRequest(in: "can you make it quieter in here?") == [.quieter])
        #expect(Paws.obviousRequest(in: "how was your day?").isEmpty)
    }

    @Test func leavesConversationToTheBrain() {
        #expect(Paws.parse("how are you feeling today?") == nil)
        #expect(Paws.parse("tell me a joke") == nil)
    }
}

@MainActor
struct KnowingTests {
    @Test func knowsItsOwnNameAndTheDay() {
        let name = Settings.shared.prefs.duckName
        #expect(Knowing.reply(to: "What's your name?", settings: .shared)?.contains(name) == true)
        #expect(Knowing.reply(to: "Who are you", settings: .shared)?.contains(name) == true)
        #expect(Knowing.reply(to: "what day is it?", settings: .shared) != nil)
        #expect(Knowing.reply(to: "tell me a joke", settings: .shared) == nil)
    }

    @Test func theFactsSayWhoIsWho() {
        var prefs = Prefs()
        prefs.duckName = "Sir Waddles"
        prefs.userName = "Patrick"
        let facts = Minds.facts(prefs)
        #expect(facts.contains("Your name: Sir Waddles."))
        #expect(facts.contains("The user's name: Patrick."))
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

    @Test func loadsThePistol() throws {
        let shot = try #require(Synth.pistol)
        let seconds = Double(shot.count) / Synth.rate
        #expect(seconds > 0.2 && seconds < 1.2)
    }

    @Test func pitchesQuacksUpAndDown() throws {
        let quack = try #require(Synth.recorded)
        #expect(Synth.resample(quack, by: 1.25).count < quack.count)
        #expect(Synth.resample(quack, by: 0.8).count > quack.count)
    }
}

@MainActor
struct SeeingTests {
    @Test func keepsRowsTogether() {
        // Vision boxes: normalised, y up. Two on one row (a label and a price), one below.
        let text = Eyes.layout([
            (CGRect(x: 0.7, y: 0.8, width: 0.1, height: 0.03), "$8,000"),
            (CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.03), "Monkey Chair"),
            (CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.03), "Add to cart"),
        ])
        #expect(text == "Monkey Chair  |  $8,000\nAdd to cart")
    }

    @Test func personalInstructionsReachTheBrain() {
        var prefs = Prefs()
        prefs.customInstructions = "Always answer in Danish."
        prefs.aboutYou = "I have a cat called Pickle."
        let instructions = Minds.chatInstructions(prefs, mood: .content)
        #expect(instructions.contains("Always answer in Danish."))
        #expect(instructions.contains("Pickle"))
        #expect(!Minds.chatInstructions(Prefs(), mood: .content).contains("own instructions"))
    }
}

struct OccasionTests {
    private func date(_ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    @Test func dressesUpForTheTimeOfYear() {
        #expect(Occasion.on(date(12, 3), birthday: nil) == .christmas)
        #expect(Occasion.on(date(10, 31), birthday: nil) == .halloween)
        #expect(Occasion.on(date(10, 20), birthday: nil) == nil)
        #expect(Occasion.on(date(6, 1), birthday: nil) == nil)
    }

    @Test func birthdaysWin() {
        #expect(Occasion.on(date(12, 24), birthday: MonthDay(month: 12, day: 24)) == .birthday)
        #expect(Occasion.on(date(3, 5), birthday: MonthDay(month: 3, day: 5)) == .birthday)
    }

    @Test(arguments: [
        ("5 March", MonthDay(month: 3, day: 5)), ("march 5th", MonthDay(month: 3, day: 5)),
        ("the 24th of December", MonthDay(month: 12, day: 24)), ("5. marts", MonthDay(month: 3, day: 5)),
        ("on May 1", MonthDay(month: 5, day: 1)), ("17 okt", MonthDay(month: 10, day: 17)),
    ])
    func readsBirthdays(text: String, expected: MonthDay) {
        #expect(MonthDay.parse(text) == expected)
    }

    @Test func needsAMonthName() {
        #expect(MonthDay.parse("03/05") == nil)
        #expect(MonthDay.parse("tomorrow") == nil)
        #expect(MonthDay.parse("March 40") == nil)
    }
}

struct PartyTrickTests {
    @Test func understandsTheNewTricks() {
        #expect(Paws.parse("start a pomodoro") == [.focusTimer])
        #expect(Paws.parse("Focus timer please") == [.focusTimer])
        #expect(Paws.parse("stop the timer") == [.stopFocusTimer])
        #expect(Paws.parse("up up down down left right left right b a") == [.hunt])
        #expect(Paws.parse("invite a friend") == [.inviteFriend])
        for deed in [Deed.focusTimer, .stopFocusTimer, .hunt, .inviteFriend] { #expect(deed.isTrick) }
    }

    @Test func gossipEndsInTheRightPlaces() {
        for script in Lines.gossip {
            #expect(script.count >= 4)
            // Both ducks get a word in.
            #expect(script.contains { $0.mine } && script.contains { !$0.mine })
            let known = ["{user}", "{name}", "{friend}", "{app}"]
            for (_, line) in script {
                let placeholders = line.matches(of: /\{[a-z]+\}/).map { String($0.output) }
                #expect(placeholders.allSatisfy(known.contains))
            }
        }
    }

    @Test func everyNewMomentHasLines() {
        let moments: [Moment] = [.birthday, .christmas, .halloween, .meetingOver, .tomatoStart, .tomatoBreak, .stretchYes,
                                 .stretchDone, .stretchSkipped, .tomatoBack, .tomatoStopped, .poop, .poopGone, .huntStart,
                                 .huntHit, .huntOver, .huntMissed, .friendWon, .friendLost, .friendGone]
        for moment in moments { #expect(!(Lines.shared[moment] ?? []).isEmpty, "\(moment)") }
    }
}
