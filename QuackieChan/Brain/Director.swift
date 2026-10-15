import AppKit

/// Decides what the duck says and does. Every few seconds it glances at the front app, checks your goals with
/// built-in rules (instant, no AI needed), and now and then asks the AI brain for a take. When you break a goal
/// badly enough, it draws the gun and counts down. It also handles talking to the duck, and the things you ask
/// it to do on your Mac.
@MainActor
final class Director {
    private let window: DuckWindow
    private var duck: Duck { window.duck }
    private let minds = Minds.shared
    private var settings: Settings { .shared }
    private var prefs: Prefs { settings.prefs }
    private var feelings: Feelings { .shared }

    private var loop: Task<Void, Never>?
    private var countdown: Task<Void, Never>?
    private var countdownKey: String?

    private var lastKey = ""
    private var keySince = Date()
    private var place = Place.other
    private var placeSince = Date()
    /// What was last read off the screen, for the page it was read from.
    private var seen: (key: String, text: String?, image: CGImage?, at: Date)?
    private var lastGlance: Glance?
    private var cooldowns: [String: Date] = [:]
    private var lastComment = Date()
    private var sessionStart = Date()
    private var lastWater = Date()
    private var thinking = false
    private var lastThoughtKey = ""
    private var lastFreshLines = Date.distantPast

    init(window: DuckWindow) {
        self.window = window
        window.talk.onSend = { [weak self] said in self?.heard(said) }
    }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// For trying things out and taking screenshots: QUACKIE_DEMO=gun pulls the gun on whatever's in front,
    /// =bananas dances to pretend music, =peck pecks the front window (without closing it), =talk opens the talk box.
    func demo(_ what: String) async {
        switch what {
        case "bananas":
            window.demoMusic()
        case "peck":
            window.peck(Desk.frontWindow()) { [weak self] in self?.duck.say("No Instagram for you!") }
        case "talk":
            window.openTalk(listening: false)
            window.talk.text = "next song please"
            duck.say("Talk to me. Or press ⌃⌥Q and just say it.")
        case "gun":
            guard let glance = await Eyes.quickLook() else { return }
            let line = Lines.pick(.threat, prefs.personality, fill: ["price": "8,000", "thing": "a monkey chair", "user": prefs.userName])
            drawGun(line, on: glance, key: "demo")
        default: break
        }
    }

    func greet() {
        duck.say(Lines.pick(.hello, prefs.personality, fill: ["name": prefs.duckName, "user": prefs.userName]), hold: 8)
    }

    // MARK: Talking

    /// Something you said to the duck, typed or spoken.
    func heard(_ said: String) {
        feelings.feel(.chatted)
        let lowered = said.lowercased()
        if ["good duck", "i love you", "you're the best", "good boy", "good girl", "cute"].contains(where: lowered.contains) {
            feelings.feel(.praised)
        }
        if ["stupid", "shut up", "hate you", "dumb duck", "useless"].contains(where: lowered.contains) {
            feelings.feel(.insulted)
        }

        // Things it knows for certain, and things you ask it to remember, need no AI.
        if let reply = Knowing.reply(to: said, settings: settings) {
            say(reply)
            return
        }
        // Plain commands are done straight away, no AI needed.
        if let deeds = Paws.parse(said) {
            perform(deeds)
            return
        }
        // Goals told in your own words.
        let wantsSomething = ["i want", "i'm trying", "im trying", "help me", "i need to", "remind me to", "jeg vil", "hjælp mig"]
        let goalWords = wantsSomething.contains(where: lowered.contains) ? settings.tell(said) : []

        guard minds.canChat else {
            if !goalWords.isEmpty || wantsSomething.contains(where: lowered.contains) {
                say(goalWords.isEmpty ? Lines.pick(.noted, prefs.personality)
                    : "\(goalWords.map { "\($0.emoji) \($0.title)" }.joined(separator: ", ")). \(Lines.pick(.noted, prefs.personality))")
            } else {
                say(Lines.pick(.dunno, prefs.personality) + " (Give me a brain in Settings → Brain and I'll really talk.)")
            }
            return
        }
        window.talk.thinking = true
        duck.set(.listening)
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.window.talk.thinking = false
                if self.duck.activity == .listening { self.duck.set(.idle) }
            }
            do {
                // A fresh look at what you're looking at right now, so it can talk about it.
                var glance = await Eyes.quickLook()
                if var looked = glance, self.prefs.canSee, Eyes.canRecordScreen,
                   !self.prefs.ignoredApps.contains(looked.bundleID) {
                    await Eyes.lookCloser(at: &looked)
                    glance = looked
                }
                // Apps on the never-look list stay private, even when you ask.
                if let looked = glance, self.prefs.ignoredApps.contains(looked.bundleID) { glance = nil }
                guard let answer = try await self.minds.answer(said, context: glance) else { return }
                self.say(answer.say)
                if !answer.deeds.isEmpty { self.perform(answer.deeds, quietly: true) }
            } catch {
                Log.brain.error("Couldn't answer: \(error.localizedDescription, privacy: .public)")
                self.say(Lines.pick(.dunno, self.prefs.personality))
            }
        }
    }

    private func say(_ line: String, alarm: Bool = false) {
        duck.say(line, alarm: alarm)
    }

    // MARK: Doing things on the Mac

    /// Does what you asked, with a little show for each, asking first for anything drastic if you want that.
    /// `quietly` skips the duck's own "done" line, when the AI already said something.
    func perform(_ deeds: [Deed], quietly: Bool = false) {
        guard let deed = deeds.first else { return }
        let rest = Array(deeds.dropFirst())
        let harmless: Bool = switch deed {
        case .dance, .nap, .remind: true
        default: false
        }
        guard harmless || prefs.hands else {
            say(Lines.pick(.notAllowed, prefs.personality))
            return
        }
        if deed.isDrastic, prefs.askFirst {
            duck.say(deed.question, choices: [
                .init(title: "Yes, do it") { [weak self] in
                    self?.duck.hush()
                    self?.carryOut(deed, quietly: false) { self?.perform(rest, quietly: quietly) }
                },
                .init(title: "No") { [weak self] in
                    self?.duck.hush()
                    self?.duck.spawn(.puff)
                },
            ])
            return
        }
        carryOut(deed, quietly: quietly) { [weak self] in self?.perform(rest, quietly: quietly) }
    }

    private func carryOut(_ deed: Deed, quietly: Bool, then next: @escaping @MainActor () -> Void) {
        func finish(_ outcome: Paws.Outcome) {
            feelings.feel(outcome.failure == nil ? .helped : .landedHard)
            if let failure = outcome.failure {
                say(failure)
            } else if !quietly {
                say(Lines.pick(outcome.moment, prefs.personality, fill: outcome.fill.merging(["user": prefs.userName]) { $1 }))
            }
            next()
        }

        switch deed {
        case .quit(let app):
            // Apps get shot.
            duck.set(.aiming)
            Sounds.shared.play(.cock)
            after(0.8) { [weak self] in
                guard let self else { return }
                self.duck.bang()
                Sounds.shared.play(.gunshot)
                self.feelings.feel(.firedGun)
                let outcome = await Paws.perform(.quit(app))
                self.after(1.2) { [weak self] in if self?.duck.activity == .aiming { self?.duck.set(.idle) } }
                finish(outcome)
            }
        case .closeTab, .closeWindow:
            // Tabs and windows get pecked.
            window.peck(Desk.frontWindow()) { [weak self] in
                let outcome = await Paws.perform(deed)
                guard self != nil else { return }
                finish(outcome)
            }
        case .type, .press:
            duck.set(.typing)
            Task { [weak self] in
                let outcome = await Paws.perform(deed)
                self?.duck.set(.idle)
                finish(outcome)
            }
        case .remind(let minutes, let about):
            say("⏰ In \(minutes) minute\(minutes == 1 ? "" : "s"): \(about). " + Lines.pick(.noted, prefs.personality))
            after(Double(minutes) * 60) { [weak self] in
                guard let self else { return }
                self.duck.set(.idle)
                self.duck.say("⏰ Hey! \(about.prefix(1).uppercased() + about.dropFirst())!", alarm: true, hold: 20)
                self.duck.spawn(.exclaim)
                Sounds.shared.play(.quack)
            }
            next()
        case .dance:
            duck.set(.dancing)
            after(14) { [weak self] in if self?.duck.activity == .dancing { self?.duck.set(.idle) } }
            next()
        case .nap:
            duck.set(.sleeping)
            next()
        default:
            duck.hop()
            duck.spawn(deed == .hide("") ? .puff : .sparkle)
            Task {
                let outcome = await Paws.perform(deed)
                if case .hide = deed { self.duck.spawn(.puff) }
                if outcome.moment == .musicControl { self.duck.spawn(.note) }
                finish(outcome)
            }
        }
    }

    // MARK: Watching

    private func tick() async {
        await minds.unloadIfIdle()
        refreshLinesIfDue()
        guard !prefs.paused, !prefs.hidden, countdown == nil, !window.talk.isOpen else { return }
        if Desk.idleSeconds > 300 {
            sessionStart = Date()
            return
        }
        guard var glance = await Eyes.quickLook(), !prefs.ignoredApps.contains(glance.bundleID) else { return }
        let now = Date()
        let key = glance.key

        if key != lastKey {
            lastKey = key
            keySince = now
        }
        if glance.place != place {
            place = glance.place
            placeSince = now
        }

        // A proper look (screenshot and text) once you've settled on a page, then every 45 seconds.
        if prefs.canSee, Eyes.canRecordScreen, now.timeIntervalSince(keySince) > 1.5,
           seen?.key != key || now.timeIntervalSince(seen?.at ?? .distantPast) > 45 {
            await Eyes.lookCloser(at: &glance)
            seen = (key, glance.text, glance.image, now)
        } else if let seen, seen.key == key {
            glance.text = seen.text
            glance.image = seen.image
        }
        lastGlance = glance
        guard key == lastKey, countdown == nil, !duck.isBusy, !window.talk.isOpen else { return }

        if let verdict = rules(glance, now: now) {
            act(verdict, glance)
        } else if shouldThink(glance, now: now) {
            think(glance)
        } else if now.timeIntervalSince(lastComment) > prefs.chattiness.commentGap * 1.5, duck.bubble == nil,
                  duck.activity != .sleeping, Int.random(in: 0..<4) == 0 {
            lastComment = now
            say(Lines.pick(idleMoment, prefs.personality, fill: ["user": prefs.userName, "name": prefs.duckName]))
        }
    }

    /// Idle chatter matches the mood half the time.
    private var idleMoment: Moment {
        guard Bool.random() else { return .idle }
        return switch feelings.mood {
        case .happy: .idleHappy
        case .grumpy: .idleGrumpy
        case .bored: .idleBored
        case .sleepy: .idleSleepy
        case .loving: .idleLoving
        case .hyped: .idleHyped
        case .content: .idle
        }
    }

    /// Every half hour, if there's a brain to talk with, it writes the duck some new idle lines.
    private func refreshLinesIfDue() {
        guard minds.canChat, Date().timeIntervalSince(lastFreshLines) > 30 * 60, !thinking else { return }
        lastFreshLines = Date()
        let personality = prefs.personality
        Task { [minds] in
            let lines = await minds.freshLines()
            if !lines.isEmpty { Lines.fresh[personality] = lines }
        }
    }

    // MARK: Rules

    private struct Verdict {
        var moment: Moment
        var key: String
        var cooldown: TimeInterval
        var threat = false
        var fill: [String: String] = [:]
    }

    /// The built-in goal rules. They need no AI: just the app, the address, the window title and text on screen.
    private func rules(_ glance: Glance, now: Date) -> Verdict? {
        let goals = Set(prefs.goals)
        let site = glance.siteName ?? glance.appName
        let minutes = Int(now.timeIntervalSince(placeSince) / 60)
        var fill = ["site": site, "thing": glance.thing ?? "that", "minutes": "\(minutes)", "user": prefs.userName,
                    "name": prefs.duckName]
        var candidates: [Verdict] = []

        if goals.contains(.saveMoney), glance.place == .shop {
            let text = glance.text?.lowercased() ?? ""
            if let price = glance.text.flatMap(Prices.highest), price >= Double(prefs.spendLimit) {
                fill["price"] = Prices.format(price)
                candidates.append(Verdict(moment: .threat, key: "spend:\(glance.key)", cooldown: 15 * 60, threat: true, fill: fill))
            } else if Place.checkoutWords.contains(where: text.contains) || (glance.url ?? "").contains("checkout") {
                candidates.append(Verdict(moment: .checkout, key: "checkout:\(site)", cooldown: 10 * 60, fill: fill))
            } else {
                candidates.append(Verdict(moment: .shopping, key: "shop:\(site)", cooldown: 30 * 60, fill: fill))
                if !prefs.canSee || !Eyes.canRecordScreen {
                    candidates.append(Verdict(moment: .cantSee, key: "cantSee", cooldown: 24 * 3600, fill: fill))
                }
            }
        }
        if goals.contains(.stopDoomscrolling), glance.place == .social {
            if minutes >= prefs.doomscrollMinutes * 2 {
                candidates.append(Verdict(moment: .doomscrollMore, key: "doom2", cooldown: 10 * 60, threat: true, fill: fill))
            } else if minutes >= prefs.doomscrollMinutes {
                candidates.append(Verdict(moment: .doomscroll, key: "doom1", cooldown: 15 * 60, fill: fill))
            }
        }
        if goals.contains(.focus), glance.place == .social || glance.place == .video, minutes >= 3 {
            candidates.append(Verdict(moment: .distracted, key: "distract:\(site)", cooldown: 20 * 60, fill: fill))
        }
        let hour = Calendar.current.component(.hour, from: now)
        if goals.contains(.sleep), hour >= prefs.bedtimeHour || hour < 5 {
            candidates.append(Verdict(moment: .bedtime, key: "bed", cooldown: 20 * 60, fill: fill))
        }
        if goals.contains(.hydrate), now.timeIntervalSince(lastWater) > 60 * 60 {
            lastWater = now
            candidates.append(Verdict(moment: .hydrate, key: "water", cooldown: 50 * 60, fill: fill))
        }
        if goals.contains(.takeBreaks), now.timeIntervalSince(sessionStart) > 50 * 60 {
            sessionStart = now
            candidates.append(Verdict(moment: .stretch, key: "stretch", cooldown: 40 * 60, fill: fill))
        }
        return candidates.first { (cooldowns[$0.key] ?? .distantPast) < now }
    }

    private func act(_ verdict: Verdict, _ glance: Glance) {
        cooldowns[verdict.key] = Date().addingTimeInterval(verdict.cooldown)
        lastComment = Date()
        let line = Lines.pick(verdict.moment, prefs.personality, fill: verdict.fill)
        if verdict.threat {
            feelings.feel(.brokeGoal)
            drawGun(line, on: glance, key: verdict.key)
        } else {
            say(line, alarm: verdict.moment == .checkout || verdict.moment == .doomscrollMore)
            duck.spawn(verdict.moment == .hydrate ? .sweat : .exclaim)
        }
    }

    // MARK: The gun

    /// Points the gun at you and counts down from five. Leave the page and you're spared; don't and BANG.
    private func drawGun(_ line: String, on glance: Glance, key: String) {
        countdown?.cancel()
        countdownKey = key
        duck.set(.aiming)
        duck.say(line, alarm: true, countdown: 5, choices: [.init(title: "I need it 🥺") { [weak self] in self?.plead() }], hold: 30)
        Sounds.shared.play(.cock)
        countdown = Task { [weak self] in
            for left in stride(from: 4, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let now = await Eyes.quickLook()
                if now == nil || now?.key != glance.key {
                    self.spared()
                    return
                }
                if left > 0 {
                    self.duck.updateCountdown(left)
                    Sounds.shared.play(.tick)
                }
            }
            self?.fire(at: glance)
        }
    }

    private func spared() {
        countdown = nil
        feelings.feel(.keptGoal)
        duck.set(.celebrating)
        say(Lines.pick(.spared, prefs.personality))
        duck.spawn(.heart)
        Sounds.shared.play(.spared)
        after(1.8) { [weak self] in if self?.duck.activity == .celebrating { self?.duck.set(.idle) } }
    }

    private func fire(at glance: Glance) {
        countdown = nil
        duck.bang()
        Sounds.shared.play(.gunshot)
        feelings.feel(.firedGun)
        duck.say(Lines.pick(.bang, prefs.personality, fill: ["user": prefs.userName]), hold: 5)
        switch prefs.enforcement {
        case .threaten:
            after(2.5) { [weak self] in if self?.duck.activity == .aiming { self?.duck.set(.idle) } }
        case .hide:
            NSRunningApplication(processIdentifier: glance.pid)?.hide()
            after(2.5) { [weak self] in if self?.duck.activity == .aiming { self?.duck.set(.idle) } }
        case .close:
            after(1.2) { [weak self] in self?.closeAfterBang(glance) }
        }
    }

    /// Flies onto the window, pecks the tab bar and closes the page you were told to leave.
    private func closeAfterBang(_ glance: Glance) {
        let front = Desk.frontWindow()
        let site = glance.siteName ?? glance.appName
        window.peck(front?.pid == glance.pid ? front : nil) { [weak self] in
            guard let self else { return }
            await Hands.close(glance)
            self.duck.say(Lines.pick(.closed, self.prefs.personality, fill: ["site": site, "user": self.prefs.userName]))
        }
    }

    private func plead() {
        countdown?.cancel()
        countdown = nil
        if let key = countdownKey { cooldowns[key] = Date().addingTimeInterval(60 * 60) }
        duck.set(.idle)
        say(Lines.pick(.snooze, prefs.personality))
    }

    // MARK: The AI brain

    private func shouldThink(_ glance: Glance, now: Date) -> Bool {
        guard !thinking, minds.canSee, duck.bubble == nil else { return false }
        let gap = prefs.chattiness.commentGap
        let since = now.timeIntervalSince(lastComment)
        // Somewhere new is worth a comment sooner than the same old tab.
        return glance.key != lastThoughtKey ? since > gap / 2 : since > gap * 2
    }

    private func think(_ glance: Glance) {
        thinking = true
        lastThoughtKey = glance.key
        Task { [weak self, minds] in
            defer { self?.thinking = false }
            do {
                guard let take = try await minds.react(to: glance) else { return }
                Log.brain.debug("Thought (\(take.mood.rawValue, privacy: .public)): \(take.line, privacy: .private)")
                self?.say(take, about: glance)
            } catch {
                Log.brain.error("The brain couldn't think: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func say(_ take: Take, about glance: Glance) {
        // By the time the model has answered you may have moved on.
        guard lastKey == glance.key, countdown == nil, !duck.isBusy, !window.talk.isOpen else { return }
        lastComment = Date()
        let hasGoals = !prefs.goals.isEmpty || !prefs.wishes.isEmpty
        switch take.mood {
        case .chill:
            // Small models call most things chill; how often those lines get said depends on chattiness.
            let odds = switch prefs.chattiness { case .quiet: 0; case .normal: 3; case .chaos: 1 }
            if odds > 0, Int.random(in: 0..<odds) == 0 { say(take.line) }
        case .threat where hasGoals && (cooldowns["ai:\(glance.key)"] ?? .distantPast) < Date():
            cooldowns["ai:\(glance.key)"] = Date().addingTimeInterval(15 * 60)
            feelings.feel(.brokeGoal)
            drawGun(take.line, on: glance, key: "ai:\(glance.key)")
        case .praise:
            feelings.feel(.keptGoal)
            say(take.line)
            duck.set(.celebrating)
            after(1.6) { [weak self] in if self?.duck.activity == .celebrating { self?.duck.set(.idle) } }
        default:
            say(take.line, alarm: take.mood == .warn)
        }
    }

    // MARK: Helpers

    private func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            await work()
        }
    }
}
