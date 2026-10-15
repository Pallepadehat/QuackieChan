import SwiftUI

/// The settings window: a sidebar like System Settings, a live duck on every page that needs one.
struct SettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case duck, personality, goals, music, brain, talk, hands, privacy, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .duck: "Duck"
            case .personality: "Personality"
            case .goals: "Goals"
            case .music: "Music"
            case .brain: "Brain"
            case .talk: "Talk"
            case .hands: "Hands"
            case .privacy: "Privacy"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .duck: "bird.fill"
            case .personality: "theatermasks.fill"
            case .goals: "target"
            case .music: "music.note"
            case .brain: "brain.head.profile"
            case .talk: "bubble.left.and.text.bubble.right.fill"
            case .hands: "hand.raised.fill"
            case .privacy: "lock.fill"
            case .about: "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .duck: .orange
            case .personality: .pink
            case .goals: .green
            case .music: .purple
            case .brain: .indigo
            case .talk: .blue
            case .hands: .teal
            case .privacy: .gray
            case .about: .secondary
            }
        }

        static let groups: [(String?, [Page])] = [
            (nil, [.duck, .personality]),
            ("Keeping you honest", [.goals, .music]),
            ("Smarts", [.brain, .talk, .hands]),
            (nil, [.privacy, .about]),
        ]
    }

    @State private var page: Page? = .duck

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                SidebarHeader()
                ForEach(Array(Page.groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group.1) { page in
                            Label { Text(page.title) } icon: { SettingsIcon(symbol: page.symbol, tint: page.tint) }
                                .tag(page)
                        }
                    } header: {
                        if let title = group.0 { Text(title) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
        } detail: {
            Group {
                switch page ?? .duck {
                case .duck: DuckPage()
                case .personality: PersonalityPage()
                case .goals: GoalsPage()
                case .music: MusicPage()
                case .brain: BrainPage()
                case .talk: TalkPage()
                case .hands: HandsPage()
                case .privacy: PrivacyPage()
                case .about: AboutPage()
                }
            }
            .navigationTitle((page ?? .duck).title)
        }
    }
}

// MARK: - Pieces

/// A white symbol on a coloured rounded square, like System Settings.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

/// The duck at the top of the sidebar, with its name and how it feels.
private struct SidebarHeader: View {
    let settings = Settings.shared
    var body: some View {
        HStack(spacing: 10) {
            LiveDuck(mode: .idle, size: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text(settings.prefs.duckName).font(.headline).lineLimit(1)
                Text("\(settings.prefs.personality.emoji) \(settings.prefs.personality.name)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .selectionDisabled()
    }
}

/// A big card with a glass background on macOS 26 and later.
private struct HeroCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(macOS 26, *) {
            content.padding(18).frame(maxWidth: .infinity).glassEffect(.regular, in: shape)
        } else {
            content.padding(18).frame(maxWidth: .infinity).background(.regularMaterial, in: shape)
        }
    }
}

private extension View {
    /// The new tabs picker style on macOS 27, segmented before.
    @ViewBuilder func tabsPicker() -> some View {
        if #available(macOS 27, *) {
            pickerStyle(.tabs)
        } else {
            pickerStyle(.segmented)
        }
    }
}

/// The duck, animated, doing one thing over and over: for previews.
struct LiveDuck: View {
    enum Mode: String, CaseIterable, Identifiable {
        case idle, waddle, dance, bananas, gun, typing, sleep, petted

        var id: String { rawValue }

        var title: String {
            switch self {
            case .idle: "Chill"
            case .waddle: "Waddle"
            case .dance: "Dance"
            case .bananas: "Bananas"
            case .gun: "Or else"
            case .typing: "Type"
            case .sleep: "Nap"
            case .petted: "Pet"
            }
        }
    }

    var mode: Mode
    var size: CGFloat
    var skin: DuckSkin? = nil
    var mood: Feelings.Mood = .content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            DuckSprite(skin: skin ?? Settings.shared.prefs.skin, pose: pose(at: t))
                .frame(width: size, height: size)
                .offset(y: lift(at: t))
        }
    }

    private func lift(at t: TimeInterval) -> CGFloat {
        switch mode {
        case .bananas, .dance: (t.truncatingRemainder(dividingBy: 0.5) < 0.17) ? -size * 0.05 : 0
        default: 0
        }
    }

    private func pose(at t: TimeInterval) -> Pose {
        let beat = Int(t / 0.5)
        let half = t.truncatingRemainder(dividingBy: 0.5) < 0.25
        var pose = Pose()
        pose.bodyY = Int(t / 1.1) % 2
        let blinking = t.truncatingRemainder(dividingBy: 3.7) < 0.14
        switch mode {
        case .idle:
            pose.eyes = blinking ? .blink : (mood == .grumpy ? .angry : mood == .sleepy ? .sleepy : .open)
        case .waddle:
            let phase = Int(t / 0.14) % 4
            pose.legs = phase < 2 ? .stepA : .stepB
            pose.bodyY = phase % 2
        case .dance:
            pose.eyes = .happy
            pose.wing = beat % 2 == 0 ? .up : .forward
            pose.legs = beat % 2 == 0 ? .stepA : .stepB
            pose.headY = half ? 1 : 0
            pose.beakOpen = half && beat % 2 == 0
        case .bananas:
            pose.eyes = .happy
            pose.dealWithIt = true
            pose.fingers = true
            pose.pump = beat % 2 == 0 ? 1 : 2
            pose.beakOpen = half
            pose.headY = half ? 2 : 0
            pose.legs = beat % 2 == 0 ? .stepA : .stepB
        case .gun:
            pose.gun = true
            pose.wing = .forward
            pose.eyes = .angry
            pose.muzzleFlash = t.truncatingRemainder(dividingBy: 2.5) < 0.15
            pose.beakOpen = t.truncatingRemainder(dividingBy: 2.5) > 1.6 && half
        case .typing:
            pose.laptop = true
            pose.legs = .tucked
            pose.bodyY = 3
            pose.lookY = 1
            pose.wing = Int(t / 0.1) % 2 == 0 ? .typingA : .typingB
        case .sleep:
            pose.eyes = .blink
            pose.legs = .tucked
            pose.bodyY = 3 + Int(t / 1.8) % 2
            pose.headY = 1
        case .petted:
            pose.eyes = .happy
            pose.blush = true
            pose.headY = 1
        }
        return pose
    }
}

// MARK: - Duck

private struct DuckPage: View {
    @Bindable var settings = Settings.shared
    @State private var mode = LiveDuck.Mode.idle

    var body: some View {
        Form {
            Section {
                HeroCard {
                    VStack(spacing: 10) {
                        LiveDuck(mode: mode, size: 170)
                        TextField("Name", text: $settings.prefs.duckName)
                            .font(.custom(Fonts.display, size: 24).weight(.bold))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.plain)
                        Picker("Try", selection: $mode) {
                            ForEach(LiveDuck.Mode.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .tabsPicker()
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section("Pick your duck") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                    ForEach(DuckSkin.all) { skin in
                        SkinTile(skin: skin, chosen: settings.prefs.skinID == skin.id) {
                            withAnimation(.snappy) { settings.prefs.skinID = skin.id }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Picker("Size", selection: $settings.prefs.size) {
                    ForEach(DuckSize.allCases) { Text($0.name).tag($0) }
                }
                .tabsPicker()
                Toggle(isOn: $settings.prefs.wander) {
                    Text("Wander, fly and climb on windows")
                    Text("Waddles about, flies up onto your windows and hops between them. Move a window and it falls off.")
                }
                Toggle(isOn: $settings.prefs.sounds) {
                    Text("Sounds")
                    Text("Quacks, a very real-sounding gun, and the click-clack of it being cocked.")
                }
                VoicePicker()
                    .disabled(!settings.prefs.sounds)
            }
        }
        .formStyle(.grouped)
    }
}

/// Which voice it talks in, with a button to hear each.
private struct VoicePicker: View {
    @Bindable var settings = Settings.shared

    var body: some View {
        LabeledContent {
            HStack {
                Picker("Voice", selection: $settings.prefs.voice) {
                    ForEach(Voice.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: settings.prefs.voice) { _, voice in sample(voice) }
                Button("Hear It", systemImage: "speaker.wave.2.fill") { sample(settings.prefs.voice) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(settings.prefs.voice == .off)
            }
        } label: {
            Text("Voice")
            Text(settings.prefs.voice.detail)
        }
    }

    private func sample(_ voice: Voice) {
        let line = Lines.pick(.hello, settings.prefs.personality, fill: ["name": settings.prefs.duckName])
        Sounds.shared.babble(line, personality: settings.prefs.personality, voice: voice)
    }
}

private struct SkinTile: View {
    let skin: DuckSkin
    let chosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 2) {
                if chosen {
                    LiveDuck(mode: .petted, size: 64, skin: skin)
                } else {
                    DuckSprite(skin: skin, pose: Pose()).frame(width: 64, height: 64)
                }
                Text(skin.name).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(chosen ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(chosen ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(skin.name)
    }
}

// MARK: - Personality

private struct PersonalityPage: View {
    @Bindable var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Personality.allCases) { personality in
                        PersonalityCard(personality: personality, chosen: settings.prefs.personality == personality) {
                            withAnimation(.snappy) { settings.prefs.personality = personality }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Who is it?")
            } footer: {
                Text("Changes everything it says, how its AI brain talks, and the pitch of its voice.")
            }
            Section {
                TextField("Your name", text: $settings.prefs.userName, prompt: Text("Optional"))
                Picker("Chattiness", selection: $settings.prefs.chattiness) {
                    ForEach(Chattiness.allCases) { Text($0.name).tag($0) }
                }
            } footer: {
                Text("Chattiness is how often it talks on its own. It always reacts when something actually happens.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct PersonalityCard: View {
    let personality: Personality
    let chosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(personality.emoji).font(.system(size: 26))
                    Spacer()
                    if chosen { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                Text(personality.name).font(.headline)
                Text(personality.blurb).font(.callout).foregroundStyle(.secondary)
                Text("“\(Lines.own[personality]?[.poke]?.first ?? "Quack.")”")
                    .font(.custom(Fonts.display, size: 13))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(chosen ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(chosen ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Goals

private struct GoalsPage: View {
    @Bindable var settings = Settings.shared
    @State private var wish = ""

    var body: some View {
        Form {
            Section {
                ForEach(Goal.allCases) { goal in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: binding(for: goal)) {
                            HStack(spacing: 10) {
                                Text(goal.emoji).font(.title2)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(goal.title)
                                    Text(goal.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if settings.prefs.goals.contains(goal) { options(for: goal).padding(.leading, 38) }
                    }
                }
            } header: {
                Text("Goals")
            } footer: {
                Text("These work without any AI: the duck checks the app, the page's address and (if it can see) the text on screen.")
            }
            Section {
                WishList(wishes: $settings.prefs.wishes)
                HStack {
                    TextField("Tell it something", text: $wish, prompt: Text("I'm learning Spanish, so no Netflix in English"))
                        .onSubmit(add)
                    Button("Tell", action: add).disabled(wish.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("In your own words")
            } footer: {
                Text("Matching goals switch on by themselves; the AI brain reads the rest, most important first.")
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        settings.tell(wish)
        wish = ""
    }

    private func binding(for goal: Goal) -> Binding<Bool> {
        Binding {
            settings.prefs.goals.contains(goal)
        } set: { on in
            settings.prefs.goals.removeAll { $0 == goal }
            if on { settings.prefs.goals.append(goal) }
        }
    }

    @ViewBuilder private func options(for goal: Goal) -> some View {
        switch goal {
        case .saveMoney:
            Stepper("Gun comes out over \(settings.prefs.spendLimit) (any currency)",
                    value: $settings.prefs.spendLimit, in: 10...100_000, step: settings.prefs.spendLimit < 100 ? 10 : 50)
        case .stopDoomscrolling:
            Stepper("Warn after \(settings.prefs.doomscrollMinutes) minutes", value: $settings.prefs.doomscrollMinutes, in: 1...120)
        case .sleep:
            Stepper("Bedtime \(settings.prefs.bedtimeHour):00", value: $settings.prefs.bedtimeHour, in: 18...23)
        default:
            EmptyView()
        }
    }
}

/// The things you told the duck. On macOS 27 you can drag them into order of importance.
private struct WishList: View {
    @Binding var wishes: [String]

    var body: some View {
        if wishes.isEmpty {
            Text("Nothing yet.").foregroundStyle(.secondary)
        } else if #available(macOS 27, *) {
            VStack(spacing: 0) {
                ForEach(wishes, id: \.self) { wish in row(wish) }
                    .reorderable()
            }
            .reorderContainer(for: String.self, itemID: \.self) { difference in
                let moving = difference.sources
                wishes.removeAll { moving.contains($0) }
                switch difference.destination.position {
                case .before(let other):
                    let index = wishes.firstIndex(of: other) ?? wishes.endIndex
                    wishes.insert(contentsOf: moving, at: index)
                case .end:
                    wishes.append(contentsOf: moving)
                }
            }
        } else {
            ForEach(wishes, id: \.self) { wish in row(wish) }
        }
    }

    private func row(_ wish: String) -> some View {
        HStack {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Text(wish)
            Spacer()
            Button(role: .destructive) {
                wishes.removeAll { $0 == wish }
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Music

private struct MusicPage: View {
    @Bindable var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                HeroCard {
                    HStack(spacing: 24) {
                        VStack { LiveDuck(mode: .dance, size: 110); Text("Dancing").font(.caption) }
                        VStack { LiveDuck(mode: .bananas, size: 110); Text("Bananas").font(.caption) }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                Toggle(isOn: $settings.prefs.dance) {
                    Text("Dance to music")
                    Text("Spotify, Music, and music sites in the front browser tab (Apple Music, YouTube Music, SoundCloud…).")
                }
                Toggle(isOn: $settings.prefs.goBananas) {
                    Text("Go completely bananas")
                    Text("After a minute of good music: deal-with-it shades and two middle fingers, right at you.")
                }
                .disabled(!settings.prefs.dance)
            } footer: {
                Text("It vibes first, dances after about 20 seconds, then loses it. It only asks music apps what's playing when "
                     + "sound is actually coming out of your Mac, and never opens them.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Brain

private struct BrainPage: View {
    @Bindable var settings = Settings.shared
    let library = ModelLibrary.shared

    var body: some View {
        Form {
            Section {
                Picker("Seeing brain", selection: $settings.prefs.brainModelID) {
                    Text("Built-in rules only").tag(String?.none)
                    Text("Apple Intelligence").tag(Optional(appleBrainID)).disabled(!AppleBrain.isAvailable)
                    ForEach(BrainModel.vision) { model in
                        Text(model.name).tag(Optional(model.id)).disabled(!library.isInstalled(model))
                    }
                }
                Picker("Talking brain", selection: $settings.prefs.chatModelID) {
                    Text("Same as the seeing brain").tag(String?.none)
                    Text("Apple Intelligence").tag(Optional(appleBrainID)).disabled(!AppleBrain.isAvailable)
                    ForEach(BrainModel.all) { model in
                        Text(model.name).tag(Optional(model.id)).disabled(!library.isInstalled(model))
                    }
                }
            } footer: {
                Text("The seeing brain looks at your front window now and then and comes up with something to say. "
                     + "The talking brain is who you chat with, and decides what to do when you ask for things. "
                     + "Everything runs on your Mac.")
            }
            Section {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "apple.intelligence", tint: .purple, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Intelligence").fontWeight(.medium)
                        Text(AppleBrain.unavailableReason ?? (AppleBrain.canSee
                            ? "Built in, nothing to download, and on this Mac it can see your screen too."
                            : "Built in, nothing to download. It can talk; it sees your screen from macOS 27."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if AppleBrain.isAvailable { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            Section("Vision models · see and talk") {
                ForEach(BrainModel.vision) { ModelRow(model: $0) }
            }
            Section("Chat models · talk, quicker") {
                ForEach(BrainModel.chat) { ModelRow(model: $0) }
            }
            Section {
                Toggle(isOn: $settings.prefs.keepBrainLoaded) {
                    Text("Keep the brain in memory")
                    Text("Off: models leave memory after 3 idle minutes and load again in a few seconds when needed.")
                }
            } footer: {
                Text("Models come from Hugging Face and run with MLX on Apple silicon.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelRow: View {
    let model: BrainModel
    let library = ModelLibrary.shared
    @Bindable var settings = Settings.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsIcon(symbol: model.kind == .vision ? "eye.fill" : "text.bubble.fill",
                         tint: model.kind == .vision ? .indigo : .blue, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name).fontWeight(.medium)
                Text(model.detail).font(.caption).foregroundStyle(.secondary)
                Text("\(model.sizeText) · \(model.license)").font(.caption2).foregroundStyle(.tertiary)
                if case .failed(let message) = library.status(of: model) {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            switch library.status(of: model) {
            case .notInstalled, .failed:
                Button("Get") {
                    library.download(model) { [settings] in
                        if model.kind == .vision, settings.prefs.brainModelID == nil { settings.prefs.brainModelID = model.id }
                        if model.kind == .chat, settings.prefs.chatModelID == nil { settings.prefs.chatModelID = model.id }
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            case .downloading(let fraction):
                ProgressView(value: fraction).progressViewStyle(.circular).controlSize(.small)
                Button("Cancel") { library.cancel(model) }.buttonStyle(.borderless)
            case .installed:
                let inUse = settings.prefs.brainModelID == model.id || settings.prefs.chatModelID == model.id
                if inUse {
                    Label("In use", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
                } else {
                    Button("Use") {
                        if model.kind == .vision { settings.prefs.brainModelID = model.id } else { settings.prefs.chatModelID = model.id }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                Menu {
                    Button("Delete", role: .destructive) {
                        if settings.prefs.brainModelID == model.id { settings.prefs.brainModelID = nil }
                        if settings.prefs.chatModelID == model.id { settings.prefs.chatModelID = nil }
                        library.delete(model)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Talk

private struct TalkPage: View {
    @Bindable var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                HeroCard {
                    VStack(spacing: 8) {
                        LiveDuck(mode: .petted, size: 100)
                        Text("Press ⌃⌥Q and just talk.").font(.custom(Fonts.display, size: 20).weight(.bold))
                        Text("Or choose Talk in its right-click menu to type. Ask it anything, or to do things: "
                             + "“quit Spotify”, “next song”, “volume 30”, “close this tab”, “remind me in 10 minutes to stretch”.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                Toggle("⌃⌥Q opens the talk box and listens", isOn: $settings.prefs.talkShortcut)
                Toggle(isOn: $settings.prefs.doubleClickToTalk) {
                    Text("Double-click the duck to talk")
                    Text("Single clicks (pokes) then wait a moment, to be sure they aren't double clicks.")
                }
                PermissionRow(permission: .microphone, title: "Microphone")
            } footer: {
                if #available(macOS 26, *) {
                    Text("Speech is turned into text on your Mac with Apple's SpeechAnalyzer. Audio never leaves the Mac and is never saved.")
                } else {
                    Text("Speech is turned into text on your Mac. Audio never leaves the Mac and is never saved.")
                }
            }
            Section {
                if settings.prefs.memories.isEmpty {
                    Text("Nothing yet. Say “remember that…” or “my name is…” when you talk to it.").foregroundStyle(.secondary)
                }
                ForEach(settings.prefs.memories, id: \.self) { memory in
                    LabeledContent(memory) {
                        Button(role: .destructive) {
                            settings.prefs.memories.removeAll { $0 == memory }
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Things it remembers")
            } footer: {
                Text("Kept on your Mac and given to its brain in every conversation. “Forget everything” clears them.")
            }
            Section {
                LabeledContent("Talking brain") {
                    Text(Minds.shared.canChat ? "Ready" : "None yet. Pick one under Brain.")
                        .foregroundStyle(Minds.shared.canChat ? Color.green : .orange)
                }
            } footer: {
                Text("Without a brain, the duck still understands plain commands and goals; it just can't chat.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hands

private struct HandsPage: View {
    @Bindable var settings = Settings.shared
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.prefs.hands) {
                    Text("Let the duck use your Mac")
                    Text("When you ask, it opens, quits and hides apps, controls music and volume, opens websites, "
                         + "closes and opens tabs, switches dark mode, presses shortcuts and types. It shoots apps to quit them and pecks tabs closed.")
                }
                Toggle(isOn: $settings.prefs.askFirst) {
                    Text("Ask before anything drastic")
                    Text("Quitting apps, closing tabs and windows, pressing keys and typing.")
                }
                .disabled(!settings.prefs.hands)
            }
            Section {
                PermissionRow(permission: .accessibility, title: "Accessibility")
            } footer: {
                Text("Needed for shortcuts, typing, and closing or minimising windows of apps that aren't browsers. "
                     + "Apps, music, volume and browser tabs work without it (macOS asks once per app the duck talks to).")
            }
            Section("Things to try") {
                ForEach(["Open Notes", "Quit Spotify", "Hide Slack", "Next song", "Volume 30", "Close this tab",
                         "Search for duck facts", "Dark mode", "Press cmd+shift+n", "Remind me in 15 minutes to stand up"], id: \.self) {
                    Label($0, systemImage: "quote.bubble").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy

private struct PrivacyPage: View {
    @Bindable var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.prefs.canSee) {
                    Text("Let the duck see the front window")
                    Text("A small picture now and then, read on your Mac to spot prices and what you're up to. Never saved or sent anywhere.")
                }
                .onChange(of: settings.prefs.canSee) { _, on in
                    if on, !Eyes.canRecordScreen { Eyes.askToRecordScreen() }
                }
                PermissionRow(permission: .screenRecording, title: "Screen Recording")
            } header: {
                Text("Seeing")
            } footer: {
                Text("Without it, the duck still knows the app and, in Safari and Chrome-style browsers, the page's address.")
            }
            Section {
                Picker("When the countdown runs out", selection: $settings.prefs.enforcement) {
                    ForEach(Enforcement.allCases) { Text($0.name).tag($0) }
                }
                if settings.prefs.enforcement == .close {
                    PermissionRow(permission: .accessibility, title: "Accessibility")
                }
            } header: {
                Text("Tough love")
            } footer: {
                Text("Browser tabs are only closed if you're still on the same page. Other apps get their close button pressed, "
                     + "so unsaved work still asks to be saved. The duck never quits apps on its own, buys, deletes or types.")
            }
            Section {
                ForEach(settings.prefs.ignoredApps, id: \.self) { id in
                    LabeledContent(appName(id)) {
                        Button(role: .destructive) {
                            settings.prefs.ignoredApps.removeAll { $0 == id }
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
                Menu("Add a Running App") {
                    ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }, id: \.processIdentifier) { app in
                        if let id = app.bundleIdentifier, !settings.prefs.ignoredApps.contains(id) {
                            Button(app.localizedName ?? id) { settings.prefs.ignoredApps.append(id) }
                        }
                    }
                }
            } header: {
                Text("Never look at")
            } footer: {
                Text("The duck doesn't look at all while these are in front. Password managers are on the list from the start.")
            }
        }
        .formStyle(.grouped)
    }

    private func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

// MARK: - About

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            LiveDuck(mode: .dance, size: 180)
            Text("Quackie Chan").font(.custom(Fonts.display, size: 34).weight(.bold))
            Text("A tiny duck that lives on your screen and keeps you honest.\nEverything runs on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") · MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack {
                Link("GitHub", destination: URL(string: "https://github.com/Pallepadehat/QuackieChan")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Report a Bug", destination: URL(string: "https://github.com/Pallepadehat/QuackieChan/issues/new/choose")!)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
