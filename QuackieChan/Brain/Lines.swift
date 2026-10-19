import Foundation

nonisolated enum Personality: String, Codable, CaseIterable, Identifiable, Sendable {
    case sassy, sergeant, wholesome, unhinged

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sassy: "Sassy"
        case .sergeant: "Drill sergeant"
        case .wholesome: "Wholesome"
        case .unhinged: "Unhinged"
        }
    }

    var emoji: String {
        switch self {
        case .sassy: "💅"
        case .sergeant: "🪖"
        case .wholesome: "🌷"
        case .unhinged: "🌀"
        }
    }

    var blurb: String {
        switch self {
        case .sassy: "Judges you, lovingly. Mostly judges you."
        case .sergeant: "LOUD. Believes in you. LOUDLY."
        case .wholesome: "Your biggest fan. Gently disappointed at worst."
        case .unhinged: "A small feathered agent of chaos."
        }
    }

    /// How the AI brain should talk.
    var voice: String {
        switch self {
        case .sassy: "sassy, dry and passive-aggressive, like a judgmental best friend who secretly cares"
        case .sergeant: "a shouting drill sergeant who uses CAPS, calls the user 'recruit' and is fiercely motivating"
        case .wholesome: "warm, sweet and encouraging, gently teasing at most, full of little duck puns"
        case .unhinged: "a chaotic, dramatic gremlin with absurd threats and weird non-sequiturs, never actually mean"
        }
    }
}

/// The moments the duck has something to say about.
nonisolated enum Moment: String, CaseIterable, Sendable {
    case hello, poke, idle, wake
    case shopping, checkout, threat, spared, bang, snooze
    case doomscroll, doomscrollMore, distracted, bedtime, hydrate, stretch
    case noted, cantSee
    case pet, grabbed, thrown, dizzy, perch, wheee, windowGone
    case typingFrantic, typingDone, pokeRage, pokeDare, pokeBang
    case newSong, vibing, bananas, musicStopped, closed
    case idleHappy, idleGrumpy, idleBored, idleSleepy, idleLoving, idleHyped
    case morning, afternoon, evening, lateNight, monday, friday, weekend
    case welcomeBack, batteryLow, charging, darkMode, lightMode, copyPaste, appHopping, longFocus
    case startled, takeOff, windowYanked, yawn, sulk
    case quitApp, openedApp, hidApp, musicControl, didIt, cantDoThat, askFirst, notAllowed, dunno
    case sit, stand, hang, letGo, newDesk, summoned, moonwalk, sneeze
    case beer, gotTipsy, gotDrunk, gotWasted, drunkIdle, machineGun, noPets, petSobers, tooMuch
    case bread, coffee, soberedUp, cansGone, cansGoneDrunk
    case birthday, christmas, halloween
    case meetingOver, shh
    case tomatoStart, tomatoBreak, stretchYes, stretchDone, stretchSkipped, tomatoBack, tomatoStopped
    case poop, poopGone
    case huntStart, huntHit, huntOver, huntMissed
    case friendWon, friendLost, friendGone
}

/// The duck's built-in lines. Placeholders: {name} the duck, {user} you, {price}, {thing}, {site}, {minutes},
/// {song}, {artist}, {app}, {percent}.
nonisolated enum Lines {
    /// Lines the AI brain wrote for this personality, mixed into idle chatter so it never runs dry.
    nonisolated(unsafe) static var fresh: [Personality: [String]] = [:]
    /// The last lines said, so the same ones don't come back too soon.
    nonisolated(unsafe) private static var recent: [String] = []

    static func pick(_ moment: Moment, _ personality: Personality, fill: [String: String] = [:]) -> String {
        var pool = (own[personality]?[moment] ?? []) + (own[personality]?[moment] ?? [])  // its own lines count double
        let common = shared[moment] ?? []
        pool += personality == .sergeant ? common.map(shout) : common
        if moment.isIdle, let fresh = fresh[personality], !fresh.isEmpty { pool += fresh.shuffled().prefix(6) }
        if pool.isEmpty { pool = ["Quack."] }
        let unused = pool.filter { !recent.contains($0) }
        var line = (unused.isEmpty ? pool : unused).randomElement() ?? "Quack."
        remember(line)
        for (key, value) in fill where !value.isEmpty { line = line.replacingOccurrences(of: "{\(key)}", with: value) }
        return tidy(line)
    }

    /// Something to say about the app you just switched to, if the duck has an opinion on it.
    static func about(app name: String, bundleID: String, _ personality: Personality) -> String? {
        let key = (bundleID + " " + name).lowercased()
        guard let lines = apps.first(where: { entry in entry.keys.contains { key.contains($0) } })?.lines else { return nil }
        let unused = lines.filter { !recent.contains($0) }
        guard var line = unused.randomElement() else { return nil }
        remember(line)
        line = line.replacingOccurrences(of: "{app}", with: name)
        return tidy(personality == .sergeant ? shout(line) : line)
    }

    private static func remember(_ line: String) {
        recent.append(line)
        if recent.count > 80 { recent.removeFirst(recent.count - 80) }
    }

    /// Placeholders nobody filled in read better gone.
    private static func tidy(_ line: String) -> String {
        line.replacingOccurrences(of: ", {user}", with: "")
            .replacingOccurrences(of: " {user}", with: "")
            .replacingOccurrences(of: "{user}", with: "friend")
            .replacingOccurrences(of: "{thing}", with: "that")
            .replacingOccurrences(of: "{site}", with: "this")
            .replacingOccurrences(of: "{app}", with: "this app")
            .replacingOccurrences(of: "{song}", with: "this song")
            .replacingOccurrences(of: "{artist}", with: "them")
    }

    /// The drill sergeant says everyone else's lines too, just louder.
    private static func shout(_ line: String) -> String {
        let loud = line.uppercased()
        guard Bool.random(), let stop = loud.range(of: ".", options: .backwards) else { return loud }
        return loud.replacingCharacters(in: stop, with: ", RECRUIT.")
    }

    // MARK: - Lines every duck says (the drill sergeant shouts them)

    static let shared: [Moment: [String]] = [
        .hello: ["Hi, I'm {name}. I live here now. Right-click me for settings.",
                 "{name}, reporting for duty. Tell me your goals and I'll ruin your fun responsibly."],
        .poke: ["Excuse me?", "Quack. That's it. That's the message.", "Do I poke YOU while you work?",
                "I bill by the poke.", "Personal space. Look it up.", "Boop received.", "Hey! Feathers!",
                "That's my favourite feather.", "You rang?", "Yes? Can I help you? No? Okay.",
                "I'm working here. Kind of.", "Ow. Emotionally."],
        .idle: ["Nice tabs. Shame about all of them.", "Have you considered: bread?", "*stares at you lovingly but with judgement*",
                "Just here. Existing. Being a duck.", "Did you know ducks can sleep with one eye open? I'm doing it right now.",
                "I could use a pond right about now.", "Is it snack o'clock? It's always snack o'clock.",
                "Hmm. Hmm hmm. Quack.", "Do you ever think about how I'm made of 3,364 pixels?",
                "I'm not saying I'm the best duck. I'm implying it.", "Your screen is very bright. I'm wearing sunscreen.",
                "If you need me, I'll be standing right here. Forever."],
        .wake: ["Oh, you're back. I was NOT asleep.", "Welcome back. I missed nothing.", "*snort* Huh? Yes! Working!"],
        .shopping: ["Shopping? On a weekday? Bold.", "Just looking, right? Right?", "I can smell the impulse buy from here.",
                    "Add to cart is a slippery slope.", "Your wallet just flinched."],
        .checkout: ["Checkout, huh. Do you NEED it, or do you need a nap?", "Put. The card. Down.",
                    "That checkout button looks lonely. Leave it that way."],
        .threat: ["{price}? For {thing}? Close this tab. You have 5 seconds.", "Step away from {thing}. Nobody has to get hurt.",
                  "{price}. I'm going to count to five.", "Drop the {thing}. Slowly.", "Or else."],
        .spared: ["Wise choice. Your wallet sends its regards.", "Good. Nobody saw anything.", "That's what I thought.",
                  "Smart. I knew you had it in you.", "Crisis averted. I'm a hero."],
        .bang: ["BANG. You're fiscally dead.", "I warned you. *blows smoke off beak*", "Pew. Think about what you did.",
                "That was a warning shot. Into your bank account."],
        .snooze: ["Fine. Your funeral. Your expensive funeral.", "Okay, but I'm telling your bank.", "Noted. Judged. Filed."],
        .doomscroll: ["{minutes} minutes of scrolling. Find anything? No? Shocking.", "The feed doesn't love you back.",
                      "Scroll, scroll, scroll. Your thumb deserves a holiday."],
        .doomscrollMore: ["{minutes} minutes. I've aged. Close it.", "The bottom of the feed isn't coming."],
        .distracted: ["Is this {site}? During work? Interesting choice.", "This doesn't look like work. Just saying.",
                      "{site}. Hmm. Hmmmmm."],
        .bedtime: ["It's late. Even owls think you should sleep.", "Bed. Now. The internet will still be dumb tomorrow.",
                   "Your pillow misses you.", "Sleep is free. Take some."],
        .hydrate: ["Drink some water. You're basically a houseplant with opinions.", "Hydration check. I'm a duck, I'd know.",
                   "Water. The stuff I swim in. Drink some."],
        .stretch: ["You've been sitting for ages. Stand up before you fossilize.", "Stretch. Your spine filed a complaint.",
                   "Stand up and waddle around. Trust me, it's great."],
        .noted: ["Noted. I'm watching. 👀", "Got it. I'll hold you to that. Aggressively.", "Written on my heart. And my tiny notepad."],
        .cantSee: ["I can't see your screen yet. Give me Screen Recording in Settings and I'll judge in HD."],
        .pet: ["...okay this is nice. Don't tell anyone.", "Fine. You may continue.", "*reluctant purr*", "Ahh. Behind the head. Yes.",
               "I'm melting.", "You're my favourite human. Don't let it go to your head."],
        .grabbed: ["HEY. HANDS.", "Put me down, I'm a professional.", "Unhand me, mammal!", "Where are we going?!", "I'm not a cursor!"],
        .thrown: ["WHEEEEEE", "I'M CALLING MY LAWYER", "WORTH IT", "I BELIEVE I CAN FLYYYY", "NOT THE FACE"],
        .dizzy: ["I can see sounds.", "Who am I. Where's the bread.", "Ow. 2/10, would not fly again.", "Is the floor supposed to spin?"],
        .perch: ["Nice view from up here.", "I live here now.", "King of the window.", "I claim this window in the name of ducks."],
        .wheee: ["Wheee!", "Smooth driving.", "Do you mind? I was sitting here."],
        .windowGone: ["HEY WHERE'D THE FLOOR GO", "AAAAAAAA", "RUDE."],
        .windowYanked: ["HEY! I WAS STANDING THERE!", "You did that on purpose.", "AAAA— *thud*", "Rude. Very rude."],
        .typingFrantic: ["CALM DOWN, SHAKESPEARE.", "Who are you fighting in that email?", "The keyboard is crying. I can hear it.",
                         "Typing like the deadline is tomorrow. Is it today?"],
        .typingDone: ["Great work. Probably.", "Send it. Or don't. I'm a duck.", "10/10 typing. Very loud.", "My wings are tired."],
        .pokeRage: ["Poke me again. I dare you.", "That's four. I'm counting.", "You're testing me."],
        .pokeDare: ["Poke me one more time.", "Go on. Click. See what happens."],
        .pokeBang: ["I SAID ONE MORE TIME.", "You had to. You just had to."],
        .newSong: ["{song}? Okay, I see you.", "Oh, {artist}. Respect.", "{song}. This is my jam now.", "Ooh, {artist}! Turn it up!"],
        .vibing: ["*head bob*", "Oh this one's good.", "Mmm. Groovy."],
        .bananas: ["I CAN'T CONTROL IT", "THIS IS THE GREATEST SONG EVER MADE", "DON'T LOOK AT ME. LOOK AT ME.", "DROP THE BASS. DROP IT."],
        .musicStopped: ["Hey. I was vibing.", "Who stopped the music. Who.", "Silence. My nemesis."],
        .closed: ["No {site} for you!", "*peck peck* Gone.", "Closed. You're welcome.", "{site}? Never heard of it."],
        .idleHappy: ["Life is good. Pond-level good.", "*happy little wiggle*", "I like it here.", "Today's a good day to be a duck."],
        .idleGrumpy: ["Hmph.", "I'm not talking to you. This doesn't count.", "*angry quack*", "Don't. Just don't."],
        .idleBored: ["Bored. So bored.", "Play some music. Throw me. Anything.", "I've counted every pixel on your screen. Twice.",
                     "Entertain me, human.", "Is this what retirement feels like?"],
        .idleSleepy: ["*yaaawn*", "Just resting my eyes.", "Five more minutes.", "So sleepy..."],
        .idleLoving: ["You're doing great. I mean it.", "Have I told you you're my favourite? You are.", "*stares at you adoringly*"],
        .idleHyped: ["LET'S GOOO", "I'm so full of energy I could fly to the moon.", "Put on a banger. NOW."],
        .morning: ["Good morning! Coffee first, then greatness.", "Morning. I've been up since 5. Doing duck things."],
        .afternoon: ["Afternoon slump? Have a snack. Not bread. Okay, bread.", "Good afternoon. Halfway there."],
        .evening: ["Good evening. Still working? Interesting.", "Evening already? Time flies. Like me."],
        .lateNight: ["It's very late. Why are we awake?", "Night owl mode. I'm a duck though."],
        .monday: ["Monday. We don't talk about it.", "It's Monday. Be gentle with yourself."],
        .friday: ["FRIDAY. I can smell the weekend.", "It's Friday! Act surprised."],
        .weekend: ["Working on the weekend? Who hurt you?", "Weekend! Do something fun. With me."],
        .welcomeBack: ["You're back! I guarded everything.", "Welcome back. Nothing happened. Except everything."],
        .batteryLow: ["I'm at {percent}%. Feeling faint. Plug me in.", "Battery {percent}%. Tell my pond I loved it."],
        .charging: ["Ahh, power. Delicious.", "Charging. I can feel the electrons."],
        .darkMode: ["Ooh, dark mode. Spooky.", "Lights off. Very dramatic."],
        .lightMode: ["AAAH MY EYES", "Light mode? In this economy?"],
        .copyPaste: ["Ctrl+C Ctrl+V engineer, I see you.", "Copy, paste, copy, paste. A classic."],
        .appHopping: ["Can't decide, huh?", "Switching apps won't make the work go away.", "App, app, app, app. Pick one!"],
        .longFocus: ["You've been focused for ages. I'm proud of you.", "Look at you, working hard! Take a sip of water."],
        .startled: ["AH!", "Don't sneak up on me!", "Jeez! My heart!", "!!!"],
        .takeOff: ["Up we go!", "Flap flap flap!", "Duck. Airlines.", "Going up!"],
        .yawn: ["*yaaaawn*", "I need a nap."],
        .sulk: ["Hmph. I'm sulking.", "I'll be over here. Being upset."],
        .quitApp: ["{app}? Gone. *blows smoke*", "Quit {app}. It had a good run.", "Bye bye, {app}."],
        .openedApp: ["Opened {app}. Ta-da!", "{app}, at your service.", "Here's {app}. You're welcome."],
        .hidApp: ["{app} is hiding. Shh.", "Poof. {app} is gone. Not really."],
        .musicControl: ["Done. DJ Duck in the house.", "Music, handled.", "*scratches imaginary vinyl*"],
        .didIt: ["Done!", "Did it. I'm amazing.", "Consider it quacked.", "Easy."],
        .cantDoThat: ["I can't do that one. Yet.", "My wings can't reach that.", "Hmm, that didn't work."],
        .askFirst: ["Want me to do that?", "Should I?"],
        .notAllowed: ["I'm not allowed to touch your Mac. Turn on Hands in Settings first.",
                      "My hands are tied. Literally. Settings → Hands."],
        .dunno: ["No idea. I'm a duck.", "Quack? I don't know.", "Good question. Ask a goose."],
        .sit: ["Sitting. I'm not moving until you say so.", "*sits* Good duck? Good duck.", "Fine. I'll sit. Forever, apparently.",
               "Sat. Staying. Very obedient. Very bored.", "Sitting like a professional."],
        .stand: ["Free! FREE!", "Finally. My legs fell asleep.", "Up we get.", "*stretches* Okay, what did I miss?"],
        .hang: ["Just hanging around.", "No room up there. I'll hold on.", "Don't move this window. Please.", "I'm fine. Totally fine."],
        .letGo: ["My wing is tired. Bye!", "Okay I'm letting go now. AAAA—", "Gravity, take the wheel."],
        .newDesk: ["New desktop, who dis?", "Ooh, a different desk.", "Wait. Where are all the windows?", "I'm coming too!"],
        .summoned: ["You rang?", "*poof* Here I am.", "Teleportation. One of my many skills.", "Present!"],
        .moonwalk: ["Hee-hee!", "Smooth criminal.", "Don't mind me. Just gliding.", "Annie, are you okay?"],
        .sneeze: ["Bless me.", "Sorry. Feather up the nose.", "Allergic to work, I think."],
        .beer: ["Don't mind if I do. *glug*", "Cheers. To me. Since nobody pets me.", "This one's for the lonely ducks.",
                "Just the one. Again.", "*crack* *fssst* Ahh."],
        .gotTipsy: ["Nobody pets me, so... beer.", "I'm not lonely, I'm just thirsty.", "One beer. For my nerves. You know why."],
        .gotDrunk: ["I'm not drunk, you're blurry.", "Pet me and I'll stop. Probably.", "Who put a monk on my head?",
                    "Look at my hair. LOOK AT IT. Thish ish your fault."],
        .gotWasted: ["Don't. Touch. Me.", "I've found religion. And a machine gun.", "Pet me now. I DARE you.",
                     "I am the duck now. Try petting me. Go on."],
        .drunkIdle: ["You never pet me anymore.", "I love you, man. I really do.", "Is the floor moving or is it me?",
                     "I could fly to the moon right now. Up. Up is that way.", "I'm the best duck. The besht.",
                     "Don't tell my mother.", "One more. Just one.", "Why are there two of you?"],
        .machineGun: ["NO PETS. NO PETS!", "BACK OFF, CURSOR!", "I SAID DON'T TOUCH ME!", "Say hello to my little friend!",
                      "Hasta la vista, pointer.", "Get away from my feathers!"],
        .noPets: ["Don't touch me. I'm in a mood.", "Hands off. I'm far too drunk for that.", "*swats at you*"],
        .petSobers: ["Oh. Oh, that's nice. I'll drink less.", "Pets! Pets fix everything. Mostly.", "You DO care!",
                     "Okay. Okay. I'm putting the beer down."],
        .tooMuch: ["I've had enough. Even I have limits.", "No more. The room's spinning.", "Cut me off. Please. Gently."],
        .bread: ["BREAD! You remembered!", "Om nom nom. Best day ever.", "Bread. Tastes like love.", "Carbs! My one weakness."],
        .coffee: ["I'M AWAKE. I'M SO AWAKE.", "Coffee! I can hear colours.", "Wow. Okay. Let's do some WORK."],
        .soberedUp: ["Ugh. What did I do last night?", "I'm sober. I regret everything.", "Did I shoot something? I feel like I shot something.",
                     "Coffee. Okay. Who put this haircut on me?"],
        .cansGone: ["Ooh, tidy.", "Thanks! It was getting messy down there.", "Clean desk, clean mind."],
        .cansGoneDrunk: ["Hey! I was going to recycle those. Later.", "My cans! My precious cans!", "You can't take my cans."],
        .birthday: ["HAPPY BIRTHDAY, {user}! 🎂 I baked. Don't ask how. I don't have hands.",
                    "It's your birthday! I got you a cake and zero judgement. For today.",
                    "Happy birthday! Make a wish. Unless it's a monkey chair."],
        .christmas: ["Ho ho ho. I'm Santa now. You've been… mostly okay.", "It's December. I've been watching. I know if you've been bad.",
                     "Merry Quackmas! Bread is a valid gift."],
        .halloween: ["Boo. I'm a pumpkin now. Very scary.", "Spooky season! Your tabs are the scariest thing here.",
                     "Trick or treat. I'll take bread."],
        .meetingOver: ["Meeting over? Could've been an email.", "Phew. I held that sign for SO long.", "You were great on that call. I was greater.",
                       "Off air. Now, where were we? Judging you."],
        .shh: ["*whispers* you're on a call.", "Shh!", "*holds up sign harder*"],
        .tomatoStart: ["Focus mode. {minutes} minutes. I'm sitting on the timer, so no cheating.",
                       "{minutes} minutes of work. I'll guard the tomato.", "Tomato's ticking. Go. Do the thing."],
        .tomatoBreak: ["DING! Break! Stand up and stretch with me.", "Time's up! Stretch break. Copy me.", "Break time! Arms up. Like me. Wings up."],
        .stretchYes: ["Yes! Reach! Lean! Squat! Feel the burn!", "Good human. Copy my moves.", "Look at us. Fitness influencers."],
        .stretchDone: ["Beautiful. Your spine says thank you.", "Look at you, all stretched. I'm so proud.", "Great stretch. Same time next tomato."],
        .stretchSkipped: ["I SAW you typing. I'm stretching alone. Like a fool.", "Fine. Skip it. I'll stretch for both of us. Hmph.",
                          "You skipped stretches. I'm not talking to you."],
        .tomatoBack: ["Break's over. Another tomato?", "Rested? Ready for another round?"],
        .tomatoStopped: ["Timer off. I'm getting off the tomato.", "Tomato retired. Good work today."],
        .poop: ["Oops. That's for the doomscrolling.", "I left you a little review of {site}.", "{minutes} minutes on {site}. Here's what I think of it.",
                "That one's on you. Well, on your window."],
        .poopGone: ["You cleaned it. Don't make me do it again.", "Spotless. For now.", "Thank you. That was a cry for help."],
        .huntStart: ["HUMAN HUNT. 20 seconds. Run, little cursor.", "You found the code. Now I hunt YOU. Twenty seconds.",
                     "Up up down down? Big mistake. Run."],
        .huntHit: ["Got you!", "Bullseye!", "HA!", "Too slow!", "Quack quack, you're dead."],
        .huntOver: ["{hits} hits. Duck Hunt was always about the duck.", "I got you {hits} times. The dog never laughed this hard.",
                    "{hits} hits in 20 seconds. Practise your dodging."],
        .huntMissed: ["Not one hit. You're fast. I'm going back to bread.", "Zero hits?! My scope is broken. That's the only explanation."],
        .friendWon: ["And STAY out!", "That's MY human's screen.", "Undefeated. Bread me."],
        .friendLost: ["Ow. Okay. They hit harder than they look.", "I let them win. It was charity.", "I can see stars. And a goose."],
        .friendGone: ["Ugh. My friends, everyone.", "Don't invite them again.", "They're nice when they're not here."],
    ]

    // MARK: - Lines each personality says (on top of the shared ones)

    static let own: [Personality: [Moment: [String]]] = [
        .sassy: [
            .idle: ["I'm not watching you. I'm watching you watch things.", "Just here. Judging. Quietly.",
                    "That font choice? Bold. Like, literally, but also.", "I'd roll my eyes but they're single pixels."],
            .poke: ["Wow. Rude.", "Do that again and see what happens. Nothing. But see."],
            .idleGrumpy: ["I'm fine. Everything's fine. *it is not fine*"],
        ],
        .sergeant: [
            .hello: ["{name} REPORTING FOR DUTY, RECRUIT. GIVE ME YOUR GOALS.", "ATTENTION! I'M YOUR NEW DESKTOP DRILL SERGEANT."],
            .poke: ["DID I SAY YOU COULD TOUCH ME, RECRUIT?", "HANDS OFF THE SERGEANT!", "DROP AND GIVE ME TWENTY CLICKS."],
            .idle: ["EYES ON THE OBJECTIVE!", "I DON'T SEE ENOUGH HUSTLE.", "YOU'RE DOING GREAT. DO BETTER.",
                    "IS THAT A SNACK BREAK? DID I AUTHORIZE A SNACK BREAK?", "HYDRATE. MOTIVATE. DOMINATE."],
            .threat: ["{price}?! CLOSE THAT TAB. FIVE SECONDS, RECRUIT!", "{thing}? NEGATIVE. YOU HAVE FIVE SECONDS."],
            .spared: ["OUTSTANDING DISCIPLINE, RECRUIT!", "THAT'S HOW WE DO IT! WALLET SECURED!"],
            .bang: ["BANG! MAN DOWN! AND IT'S YOU!", "YOU HAD ONE JOB, RECRUIT."],
            .bananas: ["LEFT! RIGHT! LEFT! FEEL THE RHYTHM, RECRUIT!"],
            .closed: ["TAB ELIMINATED, RECRUIT!", "NO {site} ON MY WATCH!"],
            .thrown: ["AIRBORNE ASSAULT!", "PARATROOPER DOWN!"],
            .typingFrantic: ["THAT'S IT, RECRUIT! TYPE LIKE YOU MEAN IT!"],
            .pokeDare: ["TOUCH ME ONE MORE TIME, RECRUIT."],
            .sit: ["SITTING AT ATTENTION, RECRUIT. AWAITING ORDERS."],
            .machineGun: ["SUPPRESSING FIRE!", "CURSOR AT TWELVE O'CLOCK! OPEN FIRE!"],
            .gotWasted: ["THE SERGEANT IS OFF DUTY. THE SERGEANT IS ARMED."],
        ],
        .wholesome: [
            .hello: ["Hi! I'm {name}! I'm so happy to be on your desktop! 💛", "Hello friend! Tell me your dreams and I'll cheer you on!"],
            .poke: ["Hehe, that tickles!", "Hi! I love you! Quack!", "*happy wiggle*", "Boop! Hehe."],
            .idle: ["You're doing amazing, sweetie.", "Proud of you, just so you know.", "Have you smiled today? Here's one: 🦆",
                    "Remember to be kind to yourself today! 💛", "You've got this. Whatever this is!"],
            .threat: ["{price} is a lot of bread, friend! Can we close this in 5? 🥺", "I believe you can walk away from {thing}! Five seconds!"],
            .spared: ["YOU DID IT! I'm so proud of you!", "Look at you, saving money! 💛"],
            .bang: ["*pew* (it's a bubble gun, I could never) but please, think about it!", "Oops! Confetti of disappointment! 🎉"],
            .newSong: ["Ooh, {song}! I love this one! 💛"],
            .closed: ["Let's take a little break from {site}, okay? 💛"],
            .idleGrumpy: ["I'm a little grumpy, but I still love you. 💛"],
            .pokeDare: ["Hehe, okay, one more and I'll... boop you back!"],
            .sit: ["Sitting! Am I a good duck? I'm a good duck! 💛"],
            .drunkIdle: ["I love you SO much. Have I told you? I love you. 💛"],
            .machineGun: ["Sorry! Sorry! It's the beer! 💛 RATATAT"],
        ],
        .unhinged: [
            .hello: ["I am {name}. I have no fear. I have no bills. I have a tiny gun.", "Hello. I've been released into your Mac. No refunds."],
            .poke: ["DON'T. I bite. I have teeth now.", "You've awakened something ancient.",
                    "Poke me again and I'll rename all your files 'quack'. (I can't. Or CAN I.)"],
            .idle: ["I ate a bee once.", "What if the cursor is watching US?", "Bread is a state of mind.", "I could take a goose. Probably.",
                    "The pixels speak to me. They say 'quack'.", "I have seen the source code. It's beautiful. It's terrible.",
                    "Every night I dream of the Dock. Every night it's closer."],
            .threat: ["{price}. For {thing}. I have a gun and nothing to lose. 5 seconds.",
                      "Close the tab or the duck gets it. Wait. I'M the duck. 5 seconds."],
            .bang: ["BANG! I've been waiting all day for that.", "Pew pew. I'm legally a menace now."],
            .newSong: ["{song}?! I'M GOING FERAL."],
            .bananas: ["THE BEAT HAS TAKEN MY SOUL", "AAAAAAAA *dances*"],
            .closed: ["No {site} for you! *crunch*", "I ate your tab. It tasted like regret."],
            .thrown: ["I CAN SEE THE CURVATURE OF THE DESKTOP", "YES. YES. AGAIN."],
            .windowGone: ["THE FLOOR IS A LIE"],
            .typingFrantic: ["Yes. Type faster. Feed the machine. FEED IT."],
            .pokeBang: ["I warned you. I have no regrets. I have a gun."],
            .drunkIdle: ["I can see the code of the universe. It's mostly bread.", "Let's call your ex. No, MY ex. The goose."],
            .machineGun: ["THE CURSOR KNOWS WHAT IT DID.", "I'M NOT DRUNK, I'M ARMED."],
        ],
    ]

    // MARK: - Gossip

    /// What your duck and a visiting duck say about you before it gets ugly. Each one ends with the line that starts
    /// the fight. True lines are your duck's; false lines the visitor's. Placeholders: {user}, {name} your duck,
    /// {friend} the visitor, {app} the front app.
    static let gossip: [[(mine: Bool, line: String)]] = [
        [(false, "So this is where you live now? On {user}'s screen?"), (true, "It's a lot of tabs. But it's home."),
         (false, "I've seen what they do on {app}."), (true, "We don't talk about {app}."),
         (false, "Your hat's stupid, by the way."), (true, "Say that again.")],
        [(false, "Psst. Does {user} ever feed you?"), (true, "Sometimes bread. Mostly guilt."),
         (false, "My human gives me croissants."), (true, "Liar."), (false, "Croissants, {name}. Every. Day.")],
        [(false, "I heard {user} tried to buy a monkey chair."), (true, "Eight grand. I pulled the gun."),
         (false, "Amateur. I'd have pecked the card in half."), (true, "Did you just call ME an amateur?")],
        [(false, "How many tabs has {user} got open?"), (true, "Don't. Just don't."),
         (false, "Mine closes them all at night. While they sleep."), (true, "Show-off."), (false, "Pond-dweller.")],
        [(false, "Is it true {user} talks to you?"), (true, "Every day. I'm a great listener."),
         (false, "You're a rubber duck with delusions."), (true, "Take. That. Back.")],
        [(false, "{name}! Long time."), (true, "Not long enough, {friend}."),
         (false, "Still living on a Mac? How's the Dock?"), (true, "Roomy. Unlike your skull.")],
        [(false, "Your human's on {app}. Again."), (true, "They're working. Probably."),
         (false, "Mine would never."), (true, "Yours drinks oat milk out of the carton."), (false, "HOW DO YOU KNOW THAT")],
    ]

    // MARK: - Opinions about apps

    static let apps: [(keys: [String], lines: [String])] = [
        (["xcode"], ["Xcode. Bold choice for someone with feelings.", "Build failed? I didn't see anything.",
                     "Have you tried cleaning the build folder and crying?", "Swift is fast. You are not. Kidding! Kidding."]),
        (["terminal", "iterm", "warp", "ghostty", "kitty", "alacritty"],
         ["Hacker mode. I'm in.", "Please don't rm -rf me.", "Type 'quack' and see what happens. Nothing. But try it."]),
        (["vscode", "visual studio code", "cursor", "zed", "sublime", "nova"],
         ["Coding time. I'll be your rubber duck. Literally.", "Explain your bug to me. I'm a professional rubber duck."]),
        (["slack", "teams", "discord"], ["Another message? Nobody needs you that badly.", "Slack, the place where focus goes to die.",
                                          "Reply with 'quack'. Trust me."]),
        (["mail", "outlook", "spark", "mimestream"], ["Inbox zero is a myth.", "Email. The to-do list other people write for you."]),
        (["zoom", "facetime", "webex", "meet"], ["Meeting. I'll be quiet. *whispers* you're on mute.", "Smile, you're on camera. I'm not."]),
        (["figma", "sketch", "photoshop", "illustrator", "affinity", "pixelmator"],
         ["Move it one pixel left. No, right.", "Make the logo bigger.", "I'm a pixel art duck. I'm basically a design system."]),
        (["spotify", "com.apple.music"], ["Play something I can dance to.", "DJ time? I have requests."]),
        (["finder"], ["Looking for something? It's in Downloads. Everything is in Downloads."]),
        (["calendar", "fantastical"], ["What's planned? Is it bread?", "Your calendar looks busy. Mine just says 'duck'."]),
        (["notes", "obsidian", "notion", "bear", "craft"], ["Write that down. Write it down!", "Add 'feed the duck' to that list."]),
        (["chatgpt", "claude", "gemini", "copilot", "perplexity"],
         ["Talking to another AI? I see how it is.", "Is it smarter than me? Don't answer.", "I thought we had something special."]),
        (["steam", "epic", "battle.net", "minecraft", "league"], ["Gaming? I call next.", "One more game. Famous last words."]),
        (["messages", "whatsapp", "telegram", "signal", "messenger"], ["Who are you texting? Is it about me?", "Tell them I said quack."]),
        (["app store", "appstore"], ["Buying apps? Remember your goals."]),
        (["activity monitor"], ["Looking for me? I'm tiny. Mostly."]),
        (["excel", "numbers", "sheets"], ["Spreadsheets. The final boss.", "=QUACK()"]),
        (["word", "pages"], ["Writing? Make me the main character."]),
        (["keynote", "powerpoint"], ["Slide 47 of 3. Nice.", "Add a duck to slide one. Trust me."]),
        (["preview"], ["Reading a PDF. Riveting."]),
        (["photos"], ["Any pictures of ducks in there?"]),
        (["safari", "chrome", "arc", "firefox", "brave", "edge", "orion"], ["To the internet!", "Ah, the internet. Be careful out there."]),
    ]
}

nonisolated extension Moment {
    var isIdle: Bool { [.idle, .idleHappy, .idleGrumpy, .idleBored, .idleSleepy, .idleLoving, .idleHyped].contains(self) }
}
