import SwiftUI

/// What the duck's right-click menu and gestures can do. Filled in by the window controller.
struct DuckActions {
    var poke: () -> Void = {}
    var dragChanged: () -> Void = {}
    var dragEnded: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }
    var talk: () -> Void = {}
    var tell: () -> Void = {}
    var sit: () -> Void = {}
    var dance: () -> Void = {}
    var bananas: () -> Void = {}
    var fly: () -> Void = {}
    var nap: () -> Void = {}
    var give: (Treat) -> Void = { _ in }
    var cleanUp: () -> Void = {}
    var openSettings: () -> Void = {}
    var togglePause: () -> Void = {}
    var hide: () -> Void = {}
    var quit: () -> Void = {}
}

/// The duck's own window: just the duck and the little things floating off it.
struct DuckStage: View {
    let duck: Duck
    let actions: DuckActions
    @Bindable var settings = Settings.shared

    /// Room around the sprite for hops and particles.
    static func size(pixel: CGFloat) -> CGSize {
        CGSize(width: CGFloat(DuckArt.canvasWidth) * pixel + 60, height: CGFloat(DuckArt.canvasHeight) * pixel + 70)
    }

    var body: some View {
        sprite.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var pixel: CGFloat { settings.prefs.size.pixel }
    private var spriteSize: CGSize {
        CGSize(width: CGFloat(DuckArt.canvasWidth) * pixel, height: CGFloat(DuckArt.canvasHeight) * pixel)
    }

    private var sprite: some View {
        ZStack(alignment: .topLeading) {
            DuckSprite(skin: settings.prefs.skin, pose: duck.pose)
                .frame(width: spriteSize.width, height: spriteSize.height)
                .scaleEffect(x: duck.facingLeft ? -1 : 1, y: 1)
                .transaction { $0.animation = nil }  // frames swap, they don't fade
            ForEach(duck.particles) { particle in
                ParticleView(particle: particle)
                    .position(x: (duck.facingLeft ? CGFloat(DuckArt.canvasWidth) - particle.at.x : particle.at.x) * pixel,
                              y: particle.at.y * pixel)
            }
        }
        .frame(width: spriteSize.width, height: spriteSize.height)
        // The smooth bits: squash and stretch from the feet, lean from the feet, bounce.
        .scaleEffect(x: 2 - duck.motion.squash, y: duck.motion.squash, anchor: .bottom)
        .rotationEffect(.degrees(duck.facingLeft ? -duck.motion.tilt : duck.motion.tilt), anchor: .bottom)
        .offset(y: -duck.motion.lift * pixel)
        .contentShape(Rectangle())
        .modifier(Taps(doubleClickToTalk: settings.prefs.doubleClickToTalk, actions: actions))
        .onHover(perform: actions.hover)
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in actions.dragChanged() }
            .onEnded { _ in actions.dragEnded() })
        .contextMenu { menu }
    }

    @ViewBuilder private var menu: some View {
        Button("Talk to \(settings.prefs.duckName)…", action: actions.talk)
        Button("Tell \(settings.prefs.duckName) a Goal…", action: actions.tell)
        Divider()
        Button(duck.staying ? "Stand Up" : "Sit", action: actions.sit)
        Menu("Tricks") {
            Button("Dance", action: actions.dance)
            Button("Go Bananas", action: actions.bananas)
            Button("Fly Somewhere", action: actions.fly)
            Button("Take a Nap", action: actions.nap)
        }
        Menu("Treats") {
            Button("🍞 Bread") { actions.give(.bread) }
            Button("☕️ Coffee") { actions.give(.coffee) }
            Button("🍺 A Beer") { actions.give(.beer) }
            if !Litter.shared.pile.cans.isEmpty {
                Divider()
                Button("Pick Up the Cans", action: actions.cleanUp)
            }
        }
        if Booze.shared.stage > .sober {
            Text("🍺 \(Booze.shared.stage.name) (\(Booze.shared.beers) beer\(Booze.shared.beers == 1 ? "" : "s"))")
        }
        Divider()
        Picker("Duck", selection: $settings.prefs.skinID) {
            ForEach(DuckSkin.all) { Text($0.name).tag($0.id) }
        }
        Picker("Personality", selection: $settings.prefs.personality) {
            ForEach(Personality.allCases) { Text("\($0.emoji) \($0.name)").tag($0) }
        }
        Divider()
        Button(settings.prefs.paused ? "Start Watching" : "Pause Watching", action: actions.togglePause)
        Button("Hide Duck", action: actions.hide)
        Button("Settings…", action: actions.openSettings)
        Divider()
        Button("Quit Quackie Chan", action: actions.quit)
    }
}

/// A click pokes the duck. With double-click-to-talk on, a double click opens the talk box instead (and single
/// clicks wait a moment to make sure they're not the first half of a double).
private struct Taps: ViewModifier {
    let doubleClickToTalk: Bool
    let actions: DuckActions

    func body(content: Content) -> some View {
        if doubleClickToTalk {
            content.onTapGesture(count: 2, perform: actions.talk).onTapGesture(perform: actions.poke)
        } else {
            content.onTapGesture(perform: actions.poke)
        }
    }
}

/// Where the bubble window should draw, set by the window controller as the duck moves.
@MainActor
@Observable
final class BubblePlacement {
    /// The bubble sits under the duck (tail up) when there's no room above it.
    var below = false
    /// How far the duck's head is from the middle of the bubble window, so the tail points at it.
    var tailShift: CGFloat = 0
    /// Where the bubble and talk box are in the window, top-left origin, for letting clicks through elsewhere.
    @ObservationIgnored var contentRect: CGRect = .zero
}

/// The bubble's own window: what the duck says, and the box you talk to it in.
struct BubbleStage: View {
    let duck: Duck
    let talk: Talk
    let placement: BubblePlacement

    static let size = CGSize(width: 340, height: 330)

    var body: some View {
        VStack(spacing: 8) {
            if placement.below { talkBox }
            if let bubble = duck.bubble {
                SpeechBubble(bubble: bubble, name: Settings.shared.prefs.duckName,
                             below: placement.below, tailShift: placement.tailShift)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5, anchor: placement.below ? .top : .bottom).combined(with: .opacity),
                        removal: .opacity.animation(.easeOut(duration: 0.08))))
                    .id(bubble.id)
            }
            if !placement.below { talkBox }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { placement.contentRect = $0 }
        .frame(width: Self.size.width, height: Self.size.height, alignment: placement.below ? .top : .bottom)
        .animation(.spring(duration: 0.25, bounce: 0.45), value: duck.bubble?.id)
        .animation(.spring(duration: 0.25, bounce: 0.3), value: talk.isOpen)
    }

    @ViewBuilder private var talkBox: some View {
        if talk.isOpen {
            TalkBox(talk: talk)
                .transition(.scale(scale: 0.8, anchor: placement.below ? .top : .bottom).combined(with: .opacity))
        }
    }
}

/// One frame of pixel duck. Frames are painted once and kept.
struct DuckSprite: View {
    let skin: DuckSkin
    let pose: Pose

    var body: some View {
        if let image = Self.image(skin: skin, pose: pose) {
            Image(decorative: image, scale: 1).resizable().interpolation(.none)
        }
    }

    private static var cache: [Int: CGImage] = [:]

    static func image(skin: DuckSkin, pose: Pose) -> CGImage? {
        var hasher = Hasher()
        hasher.combine(skin)
        hasher.combine(pose)
        let key = hasher.finalize()
        if let image = cache[key] { return image }
        if cache.count > 400 { cache.removeAll() }
        let image = DuckArt.image(skin: skin, pose: pose, scale: 1)
        cache[key] = image
        return image
    }
}

/// A little thing that floats up off the duck and fades: Zzz, hearts, BANG, smoke.
struct ParticleView: View {
    let particle: Duck.Particle
    @State private var gone = false

    var body: some View {
        content
            .offset(x: gone ? particle.drift.width : 0, y: gone ? particle.drift.height : 0)
            .scaleEffect(gone ? grownScale : 0.6)
            .opacity(gone ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.3)) { gone = true } }
            .allowsHitTesting(false)
    }

    private var grownScale: CGFloat {
        switch particle.kind {
        case .bang: 1.6
        case .smoke, .puff: 2
        default: 1.1
        }
    }

    private var pick: Int { abs(particle.id.hashValue) }

    @ViewBuilder private var content: some View {
        switch particle.kind {
        case .zzz: label("z", size: 16, color: .white)
        case .heart: Text("❤️").font(.system(size: 14))
        case .anger: Text("💢").font(.system(size: 16))
        case .sweat: Text("💦").font(.system(size: 13))
        case .exclaim: label("!", size: 22, color: .yellow)
        case .question: label("?", size: 20, color: .white)
        case .tap: label(["tap", "tik", "clack", "tap"][pick % 4], size: 10, color: .white)
        case .fire: Text("🔥").font(.system(size: 14))
        case .smoke: Circle().fill(Color.white.opacity(0.6)).frame(width: 10, height: 10)
        case .puff: Text("💨").font(.system(size: 13))
        case .bang:
            label("BANG!", size: 18, color: .white)
                .padding(.horizontal, 5)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 4))
        case .sparkle: Text("✦").font(.system(size: 14)).foregroundStyle(.yellow)
        case .note: Text(["♪", "♫", "♬"][pick % 3]).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
        case .impact: Text("💥").font(.system(size: 16))
        case .hic: label("hic!", size: 13, color: Color(red: 1, green: 0.85, blue: 0.4))
        case .beer: Text("🍺").font(.system(size: 13))
        case .coffee: Text("☕️").font(.system(size: 12))
        case .casing: RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.95, green: 0.75, blue: 0.3)).frame(width: 3, height: 6)
        case .crumb: RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.85, green: 0.6, blue: 0.3)).frame(width: 4, height: 4)
        case .ratatat:
            label(["RATATAT", "BRRRT", "TAT TAT"][pick % 3], size: 13, color: .white)
                .padding(.horizontal, 4)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 4))
        case .achoo: label("ACHOO!", size: 16, color: .white)
        }
    }

    private func label(_ text: String, size: CGFloat, color: Color) -> some View {
        Text(text)
            .font(.custom(Fonts.display, size: size).weight(.bold))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.6), radius: 0, x: 1, y: 1)
            .fixedSize()
    }
}

enum BubbleStyle {
    static let fill = Color(red: 0.17, green: 0.15, blue: 0.13)
    static let border = Color(red: 0.80, green: 0.72, blue: 0.60)
    static let tag = Color(red: 0.62, green: 0.48, blue: 0.34)
}

/// A dark speech bubble with the duck's name on a tag, like a game's dialogue box.
struct SpeechBubble: View {
    let bubble: Duck.Bubble
    let name: String
    var below = false
    var tailShift: CGFloat = 0

    var body: some View {
        VStack(spacing: 7) {
            if let countdown = bubble.countdown {
                Text("\(countdown)")
                    .font(.custom(Fonts.display, size: 34).weight(.bold))
                    .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.3))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: countdown)
            }
            Text(bubble.text)
                .font(.custom(Fonts.display, size: 16).weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !bubble.choices.isEmpty {
                HStack(spacing: 8) {
                    ForEach(bubble.choices) { choice in
                        Button(action: choice.action) {
                            Text(choice.title)
                                .font(.custom(Fonts.display, size: 12).weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(BubbleStyle.tag, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(minWidth: 120, maxWidth: 270)
        .background(BubbleShape(below: below, tailShift: tailShift).fill(BubbleStyle.fill))
        .overlay(BubbleShape(below: below, tailShift: tailShift).stroke(bubble.alarm ? Color.red : BubbleStyle.border, lineWidth: 3))
        .overlay(alignment: .top) { nameTag }
        .padding(.top, below ? 26 : 14)
        .padding(.bottom, below ? 2 : 12)
        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
    }

    private var nameTag: some View {
        Text(name)
            .font(.custom(Fonts.display, size: 13).weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(BubbleStyle.tag, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(BubbleStyle.border.opacity(0.6), lineWidth: 1.5))
            .offset(y: -13)
            .fixedSize()
    }
}

/// A rounded box with a little tail pointing at the duck, below it or (when the bubble is under the duck) above.
struct BubbleShape: Shape {
    var below = false
    /// Where the duck is relative to the middle of the bubble window.
    var tailShift: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 10, r: CGFloat = 14
        // The bubble is centred in its window, so the duck is tailShift from the bubble's middle too.
        // The tail stays on the straight edge, as close to the duck as it can get.
        let x = min(max(rect.midX + tailShift, rect.minX + r + tail), rect.maxX - r - tail)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        if below {
            path.addLine(to: CGPoint(x: x - tail, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.minY - tail))
            path.addLine(to: CGPoint(x: x + tail, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
        if !below {
            path.addLine(to: CGPoint(x: x + tail, y: rect.maxY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY + tail))
            path.addLine(to: CGPoint(x: x - tail, y: rect.maxY))
        }
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        path.closeSubpath()
        return path
    }
}
