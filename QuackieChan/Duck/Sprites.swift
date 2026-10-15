import CoreGraphics
import Foundation

// The duck is pixel art painted in code: ellipses and rectangles rasterised onto a small grid, then shaded and
// outlined like hand-drawn sprites. Painting it from a pose (instead of storing frames) lets one duck do every
// expression and animation. Only CoreGraphics and Foundation here, so scripts/make-icons.sh can draw the app icon
// from the same code.

nonisolated struct RGB: Hashable, Sendable {
    let hex: UInt32

    init(_ hex: UInt32) { self.hex = hex }

    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Poses

/// Everything about how the duck looks in one frame.
nonisolated struct Pose: Hashable, Sendable {
    enum Eyes: Hashable, Sendable { case open, blink, angry, happy, shocked, dizzy, sad, sleepy }
    enum Legs: Hashable, Sendable { case stand, stepA, stepB, tucked, dangling }
    enum Wing: Hashable, Sendable { case rest, up, forward, typingA, typingB }

    var eyes = Eyes.open
    /// Where the pupil looks: -1 back, 0 ahead, 1 at the beak; and -1 up to 1 down.
    var lookX = 0
    var lookY = 0
    var beakOpen = false
    var headX = 0
    var headY = 0
    /// Moves the whole body down (breathing, squashing, sitting).
    var bodyY = 0
    var legs = Legs.stand
    var wing = Wing.rest
    var blush = false
    var sweat = false
    /// Pointing a pistol straight at you, meme style.
    var gun = false
    var muzzleFlash = false
    var laptop = false
    /// Pixel "deal with it" shades, worn over whatever hat.
    var dealWithIt = false
    /// Two very human hands, backs toward you, both giving you the middle finger. For when the music is really good.
    var fingers = false
    /// Which hand is pumped up on this beat: 0 both level, 1 left up, 2 right up.
    var pump = 0
}

// MARK: - Skins

nonisolated enum Hat: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, headband, bandana, cap, flowers, wizard, mushroom, shades, topHat

    var id: String { rawValue }

    var name: String {
        switch self {
        case .none: "Nothing"
        case .headband: "Karate headband"
        case .bandana: "Bandana"
        case .cap: "Baseball cap"
        case .flowers: "Flower crown"
        case .wizard: "Wizard hat"
        case .mushroom: "Mushroom"
        case .shades: "Sunglasses"
        case .topHat: "Top hat"
        }
    }
}

nonisolated enum Plumage: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic, rubber, midnight, bubblegum

    var id: String { rawValue }

    var name: String {
        switch self {
        case .classic: "Classic"
        case .rubber: "Rubber duck"
        case .midnight: "Midnight"
        case .bubblegum: "Bubblegum"
        }
    }

    var palette: [Character: RGB] {
        var colors: [Character: RGB] = [
            "O": RGB(0x3B2A20), "W": RGB(0xFBF4E6), "S": RGB(0xE9DAC0), "s": RGB(0xCDB896), "L": RGB(0xFFFFFF),
            "Y": RGB(0xF5A43B), "y": RGB(0xD9782A), "m": RGB(0x6E2A1C), "E": RGB(0x1E140E), "w": RGB(0xFFFFFF),
            "F": RGB(0xF2A23A), "f": RGB(0xC9761F), "p": RGB(0xF4A3A8), "c": RGB(0x8FD8F2),
            // Hats.
            "R": RGB(0xE0453A), "r": RGB(0xA82E26), "B": RGB(0x3B5BD9), "b": RGB(0x263E9E), "D": RGB(0x3A3D4A),
            "d": RGB(0x5A5F73), "P": RGB(0xF28DB2), "G": RGB(0x5DBB63), "K": RGB(0x1D1D24), "k": RGB(0x6B6B78),
            "*": RGB(0xFFE066), "u": RGB(0xF3E3C3),
            // The gun, the hand holding it, and the laptop.
            "g": RGB(0xDCE0E6), "n": RGB(0xA9AFB8), "N": RGB(0x6E7580), "H": RGB(0xE3A97F), "h": RGB(0xB97A55),
            "l": RGB(0x9AA1AE), "e": RGB(0x5F6675), "X": RGB(0xFFF4B0), "x": RGB(0xFFB13B),
        ]
        switch self {
        case .classic: break
        case .rubber:
            colors["W"] = RGB(0xFFD84A); colors["S"] = RGB(0xF2BE2E); colors["s"] = RGB(0xD99A1C); colors["L"] = RGB(0xFFF0A0)
            colors["Y"] = RGB(0xF2762A); colors["y"] = RGB(0xC4541A); colors["F"] = RGB(0xF2762A); colors["f"] = RGB(0xC4541A)
        case .midnight:
            colors["W"] = RGB(0x5B6378); colors["S"] = RGB(0x4A5165); colors["s"] = RGB(0x3A4052); colors["L"] = RGB(0x737C94)
            colors["O"] = RGB(0x161922); colors["E"] = RGB(0xFFE066)
        case .bubblegum:
            colors["W"] = RGB(0xFFD9E4); colors["S"] = RGB(0xF5B5C7); colors["s"] = RGB(0xE291A8); colors["L"] = RGB(0xFFF0F4)
        }
        return colors
    }
}

/// Which duck: its feathers and what it wears.
nonisolated struct DuckSkin: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let plumage: Plumage
    let hat: Hat

    static let all: [DuckSkin] = [
        DuckSkin(id: "quackie", name: "Quackie Chan", plumage: .classic, hat: .headband),
        DuckSkin(id: "don", name: "Don Quackleone", plumage: .classic, hat: .bandana),
        DuckSkin(id: "bill", name: "Bill", plumage: .classic, hat: .cap),
        DuckSkin(id: "daisy", name: "Daisy", plumage: .classic, hat: .flowers),
        DuckSkin(id: "merlin", name: "Merlin", plumage: .classic, hat: .wizard),
        DuckSkin(id: "shroomie", name: "Shroomie", plumage: .classic, hat: .mushroom),
        DuckSkin(id: "norris", name: "Duck Norris", plumage: .classic, hat: .shades),
        DuckSkin(id: "rubber", name: "Rubber Ducky", plumage: .rubber, hat: .none),
        DuckSkin(id: "sir", name: "Sir Quacksalot", plumage: .midnight, hat: .topHat),
        DuckSkin(id: "bubblegum", name: "Bubblegum", plumage: .bubblegum, hat: .flowers),
    ]

    static let standard = all[0]

    static func with(id: String) -> DuckSkin { all.first { $0.id == id } ?? standard }
}

// MARK: - Painting

/// A grid of palette letters, with which body part each pixel belongs to (for shading, seams and outlines).
nonisolated private struct PixelCanvas {
    enum Part: UInt8 { case empty, leg, body, head, wing, beak, face, hat, hand, gun, laptop, effect, outline }

    let width: Int
    let height: Int
    var colors: [Character?]
    var parts: [Part]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        colors = Array(repeating: nil, count: width * height)
        parts = Array(repeating: .empty, count: width * height)
    }

    func part(_ x: Int, _ y: Int) -> Part {
        guard x >= 0, y >= 0, x < width, y < height else { return .empty }
        return parts[y * width + x]
    }

    mutating func set(_ x: Int, _ y: Int, _ color: Character, _ part: Part) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        colors[y * width + x] = color
        parts[y * width + x] = part
    }

    /// Fills an ellipse. `shade` gets the pixel's position inside it (-1...1 on both axes) and picks its colour.
    mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ part: Part,
                          only: ((Int, Int) -> Bool)? = nil, shade: (Double, Double) -> Character?) {
        for y in Int((cy - ry).rounded(.down))...Int((cy + ry).rounded(.up)) {
            for x in Int((cx - rx).rounded(.down))...Int((cx + rx).rounded(.up)) {
                let nx = (Double(x) + 0.5 - cx) / rx, ny = (Double(y) + 0.5 - cy) / ry
                guard nx * nx + ny * ny <= 1, only?(x, y) ?? true, let color = shade(nx, ny) else { continue }
                set(x, y, color, part)
            }
        }
    }

    mutating func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: Character, _ part: Part) {
        for y in y0...y1 { for x in x0...x1 { set(x, y, color, part) } }
    }

    /// Draws `rows` with its top left at (x, y). Spaces and dots are left alone.
    mutating func stamp(_ rows: [String], _ x: Int, _ y: Int, _ part: Part) {
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() where character != "." && character != " " {
                set(x + column, y + row, character, part)
            }
        }
    }

    /// Pixels of `onto` parts that touch `part` become outline, so the two read as separate pieces.
    mutating func seam(_ part: Part, onto: Set<Part>) {
        var marks: [(Int, Int)] = []
        for y in 0..<height {
            for x in 0..<width where parts[y * width + x] == part {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where onto.contains(self.part(x + dx, y + dy)) {
                    marks.append((x + dx, y + dy))
                }
            }
        }
        for (x, y) in marks { set(x, y, "O", .outline) }
    }

    /// Every clear pixel next to a painted one becomes outline: the dark edge around the whole sprite.
    mutating func outline() {
        var marks: [(Int, Int)] = []
        for y in 0..<height {
            for x in 0..<width where parts[y * width + x] == .empty {
                let touches = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                    let neighbour = part(x + dx, y + dy)
                    return neighbour != .empty && neighbour != .outline && neighbour != .effect
                }
                if touches { marks.append((x, y)) }
            }
        }
        for (x, y) in marks { set(x, y, "O", .outline) }
    }
}

nonisolated enum DuckArt {
    /// The canvas every frame is painted on, in art pixels. The duck faces right; the gun and laptop go in front.
    static let canvasWidth = 58
    static let canvasHeight = 58
    /// Where the gun's muzzle is, in canvas pixels from the top left.
    static let muzzle = CGPoint(x: 47, y: 35)
    /// Where the top of the head is, for things that float above it (Zzz, hearts).
    static let headTop = CGPoint(x: 26, y: 14)

    static func paint(_ skin: DuckSkin, _ pose: Pose) -> [[Character?]] {
        var canvas = PixelCanvas(width: canvasWidth, height: canvasHeight)
        let by = Double(pose.bodyY)
        let hx = 26 + pose.headX, hy = 24 + pose.headY + pose.bodyY

        paintLegs(&canvas, pose)

        // Body, tail and neck, lit from the top left: a pale rim on top, shade underneath.
        let feathers: (Double, Double) -> Character? = { _, ny in ny > 0.5 ? "S" : (ny < -0.82 ? "L" : "W") }
        canvas.ellipse(10, 39 + by, 5.5, 4, .body, shade: feathers)
        canvas.ellipse(6.5, 35.5 + by, 3, 2.5, .body, shade: { _, _ in "W" })
        canvas.ellipse(21, 43 + by, 13.5, 8.5, .body, shade: feathers)
        canvas.ellipse(26, 35 + by, 6.5, 6, .body, shade: { _, _ in "W" })
        // Head.
        canvas.ellipse(Double(hx), Double(hy), 9.5, 9, .head) { nx, ny in
            if ny < -0.7 && nx < 0.3 { return "L" }
            if nx < -0.6 && ny > 0.1 { return "S" }
            return "W"
        }

        paintWing(&canvas, pose)
        paintBeak(&canvas, pose, hx: hx, hy: hy)
        paintEyes(&canvas, pose, hx: hx, hy: hy)
        if pose.blush || pose.eyes == .happy { canvas.rect(hx + 1, hy + 1, hx + 2, hy + 1, "p", .face) }
        if pose.sweat {
            canvas.stamp([".c", "cc", "cc"], hx - 8, hy - 3, .effect)
        }
        // Hats sit two pixels higher than the eye line, except sunglasses, which go over it.
        paintHat(&canvas, skin.hat, hx: hx, hy: skin.hat == .shades ? hy : hy - 2)
        if pose.dealWithIt { paintDealWithIt(&canvas, hx: hx, hy: hy) }
        if pose.laptop { paintLaptop(&canvas) }
        if pose.fingers { paintFingers(&canvas, bodyY: pose.bodyY, pump: pose.pump) }
        if pose.gun { paintGun(&canvas, flash: pose.muzzleFlash) }

        canvas.outline()

        return (0..<canvasHeight).map { y in Array(canvas.colors[(y * canvasWidth)..<((y + 1) * canvasWidth)]) }
    }

    // MARK: Parts

    private static func paintLegs(_ canvas: inout PixelCanvas, _ pose: Pose) {
        func leg(_ x: Int, lift: Int = 0, reach: Int = 0) {
            canvas.rect(x, 49, x + 1, 53 - lift, "F", .leg)
            canvas.rect(x + reach, 54 - lift, x + reach + 4, 55 - lift, "F", .leg)
            canvas.rect(x + reach, 55 - lift, x + reach + 4, 55 - lift, "f", .leg)
        }
        switch pose.legs {
        case .stand: leg(16); leg(25)
        case .stepA: leg(16, lift: 1, reach: 1); leg(25, reach: -1)
        case .stepB: leg(16, reach: -1); leg(25, lift: 1, reach: 1)
        case .tucked: break
        case .dangling:
            for x in [17, 25] {
                canvas.rect(x, 49, x + 1, 55, "F", .leg)
                canvas.rect(x - 1, 54, x + 2, 56, "f", .leg)
            }
        }
    }

    private static func paintWing(_ canvas: inout PixelCanvas, _ pose: Pose) {
        let by = Double(pose.bodyY)
        let center: (Double, Double, Double, Double)
        switch pose.wing {
        case .rest: center = (18, 42 + by, 8.5, 4.5)
        case .up: center = (15, 33 + by, 7, 4)
        case .forward: center = (27, 41 + by, 8, 4)
        case .typingA: center = (28, 43 + by, 8, 3.5)
        case .typingB: center = (27, 41 + by, 8, 3.5)
        }
        canvas.ellipse(center.0, center.1, center.2, center.3, .wing) { nx, ny in
            // Two rows of feathers on the wing.
            if ny > 0.55 { return Int(((nx + 1) * 3).rounded(.down)) % 2 == 0 ? "s" : "S" }
            if ny < -0.45 { return nx < 0.5 ? "W" : "S" }
            return nx > 0.6 ? "s" : "S"
        }
    }

    private static func paintBeak(_ canvas: inout PixelCanvas, _ pose: Pose, hx: Int, hy: Int) {
        let bx = Double(hx) + 12, byy = Double(hy) + 2
        if pose.beakOpen {
            canvas.ellipse(bx, byy - 1, 5.5, 2, .beak) { _, ny in ny > 0.4 ? "y" : "Y" }
            canvas.ellipse(bx - 1, byy + 2.5, 4.5, 1.6, .beak) { _, _ in "y" }
            canvas.rect(hx + 9, Int(byy) + 1, hx + 13, Int(byy) + 1, "m", .beak)
        } else {
            canvas.ellipse(bx, byy, 5.5, 2.2, .beak) { _, ny in ny > 0.35 ? "y" : "Y" }
        }
        canvas.seam(.beak, onto: [.head])
    }

    private static func paintEyes(_ canvas: inout PixelCanvas, _ pose: Pose, hx: Int, hy: Int) {
        let ex = hx + 3, ey = hy - 4
        switch pose.eyes {
        case .open:
            let x = ex + max(-1, min(1, pose.lookX)), y = ey + max(-1, min(1, pose.lookY))
            canvas.rect(x, y, x + 1, y + 2, "E", .face)
            canvas.set(x, y, "w", .face)
        case .blink:
            canvas.rect(ex - 1, ey + 2, ex + 2, ey + 2, "E", .face)
        case .angry:
            canvas.rect(ex, ey + 1, ex + 1, ey + 2, "E", .face)
            canvas.set(ex, ey + 1, "w", .face)
            for (dx, dy) in [(-2, -2), (-1, -2), (0, -1), (1, -1), (2, 0)] { canvas.set(ex + dx, ey + dy, "E", .face) }
        case .happy:
            for (dx, dy) in [(-1, 2), (0, 1), (1, 1), (2, 2)] { canvas.set(ex + dx, ey + dy, "E", .face) }
        case .shocked:
            canvas.rect(ex - 1, ey - 1, ex + 2, ey + 3, "E", .face)
            canvas.rect(ex, ey, ex + 1, ey + 2, "w", .face)
            canvas.set(ex + 1, ey + 1, "E", .face)
        case .dizzy:
            for (dx, dy) in [(-1, 0), (1, 0), (0, 1), (-1, 2), (1, 2)] { canvas.set(ex + dx, ey + dy, "E", .face) }
        case .sad:
            canvas.rect(ex, ey + 1, ex + 1, ey + 3, "E", .face)
            canvas.set(ex, ey + 1, "w", .face)
            // Brows tilted up in the middle.
            for (dx, dy) in [(-1, -1), (0, -1), (1, -2), (2, -2)] { canvas.set(ex + dx, ey + dy, "E", .face) }
        case .sleepy:
            canvas.rect(ex - 1, ey + 1, ex + 2, ey + 1, "E", .face)
            canvas.rect(ex, ey + 2, ex + 1, ey + 2, "E", .face)
        }
    }

    private static func paintHat(_ canvas: inout PixelCanvas, _ hat: Hat, hx: Int, hy: Int) {
        // The hat only replaces head pixels in a band, so it hugs the head's shape.
        let onHead: (Int, Int) -> Bool = { _, _ in true }
        switch hat {
        case .none: return
        case .headband:
            for x in (hx - 9)...(hx + 9) {
                for y in (hy - 5)...(hy - 4) where canvas.part(x, y) == .head {
                    canvas.set(x, y, y == hy - 5 ? "R" : "r", .hat)
                }
            }
            canvas.stamp(["RR.", "rRR", ".rR", "..R", "...R"], hx - 12, hy - 5, .hat)
        case .bandana:
            canvas.ellipse(Double(hx) - 0.5, Double(hy) - 4, 10.5, 7, .hat, only: { _, y in y <= hy - 4 }) { nx, ny in
                if ny < -0.55 && nx > -0.4 && nx < 0.3 { return "d" }
                if abs(nx + ny * 0.6 - 0.1) < 0.12 { return "K" }
                return "D"
            }
            canvas.stamp(["DD.", "DdD", "DDd", ".DD", ".Dd", "..D", ".DD", "DD."], hx - 12, hy - 3, .hat)
            canvas.stamp(["D", "D", "d"], hx - 9, hy - 2, .hat)
        case .cap:
            canvas.ellipse(Double(hx) - 1, Double(hy) - 4, 10, 7, .hat, only: { _, y in y <= hy - 4 }) { nx, ny in
                ny < -0.6 && nx < 0 ? "B" : (nx > 0.55 ? "b" : "B")
            }
            canvas.rect(hx + 1, hy - 4, hx + 14, hy - 3, "b", .hat)
            canvas.rect(hx + 1, hy - 4, hx + 13, hy - 4, "B", .hat)
            canvas.rect(hx - 2, hy - 10, hx - 1, hy - 10, "w", .hat)
            canvas.set(hx - 1, hy - 6, "w", .hat)
        case .flowers:
            for (index, dx) in [-7, -4, -1, 2, 5].enumerated() {
                let x = hx + dx
                guard let top = (0..<canvas.height).first(where: { canvas.part(x, $0) == .head }) else { continue }
                let petal: Character = index % 2 == 0 ? "P" : "w"
                canvas.stamp([".\(petal).", "\(petal)Y\(petal)", ".\(petal)."], x - 1, top - 2, .hat)
                if index < 4 { canvas.set(x + 2, top, "G", .hat) }
            }
        case .wizard:
            for row in 0..<17 {
                let half = max(0, 7 - row * 7 / 16)
                let lean = row * row / 40
                let y = hy - 7 - row
                for x in (hx - half - lean)...(hx + half - lean) {
                    canvas.set(x, y, x == hx + half - lean ? "b" : "B", .hat)
                }
            }
            canvas.ellipse(Double(hx), Double(hy) - 6, 12, 2, .hat, only: onHead) { _, ny in ny > 0 ? "b" : "B" }
            for (dx, dy) in [(-3, -10), (2, -13), (-2, -17), (-5, -21), (1, -9)] { canvas.set(hx + dx, hy + dy, "*", .hat) }
        case .mushroom:
            canvas.ellipse(Double(hx), Double(hy) - 6, 12.5, 8, .hat, only: { _, y in y <= hy - 4 }) { nx, ny in
                if ny > 0.4 { return "u" }
                return nx > 0.6 ? "r" : "R"
            }
            let cap = canvas
            for (dx, dy, r) in [(-6.0, -9.0, 2.2), (1.0, -11.0, 2.4), (7.0, -7.0, 1.7), (-1.0, -6.5, 1.3), (-10.0, -6.0, 1.2)] {
                canvas.ellipse(Double(hx) + dx, Double(hy) + dy, r, r, .hat, only: { cap.part($0, $1) == .hat }) { _, _ in "w" }
            }
        case .shades:
            canvas.rect(hx + 1, hy - 4, hx + 7, hy - 1, "K", .hat)
            canvas.rect(hx - 8, hy - 4, hx, hy - 4, "K", .hat)
            canvas.set(hx + 5, hy - 3, "k", .hat)
            canvas.set(hx + 6, hy - 3, "w", .hat)
        case .topHat:
            canvas.rect(hx - 6, hy - 22, hx + 4, hy - 7, "K", .hat)
            canvas.rect(hx - 5, hy - 21, hx - 4, hy - 9, "k", .hat)
            canvas.rect(hx - 6, hy - 10, hx + 4, hy - 9, "R", .hat)
            canvas.rect(hx - 10, hy - 7, hx + 8, hy - 6, "K", .hat)
        }
        canvas.seam(.hat, onto: [.head])
    }

    /// A pistol pointed straight at you, held in a very human hand. The muzzle is the big dark circle.
    private static func paintGun(_ canvas: inout PixelCanvas, flash: Bool) {
        // Hand: palm and wrapped fingers under the grip, thumb up its left side.
        canvas.ellipse(41, 47, 6, 6.5, .hand) { nx, ny in
            if ny > 0.15 && Int(((ny + 1) * 5).rounded(.down)) % 2 == 0 && nx > -0.7 { return "h" }
            return nx > 0.55 ? "h" : "H"
        }
        canvas.ellipse(38.5, 39.5, 2.2, 3.5, .hand) { nx, _ in nx > 0.4 ? "h" : "H" }
        // Slide, seen end on, and the frame under it.
        canvas.ellipse(47, 35, 6.5, 6, .gun) { nx, ny in
            if nx < -0.55 || ny < -0.6 { return "g" }
            return nx > 0.6 || ny > 0.6 ? "N" : "n"
        }
        canvas.rect(43, 40, 51, 45, "n", .gun)
        canvas.rect(43, 40, 44, 45, "g", .gun)
        canvas.rect(50, 40, 51, 45, "N", .gun)
        canvas.rect(46, 27, 48, 28, "N", .gun)  // front sight
        // The barrel's mouth and the guide rod hole.
        canvas.ellipse(47, 35, 3.4, 3.4, .gun) { nx, ny in nx * nx + ny * ny < 0.45 ? "K" : "k" }
        canvas.ellipse(47, 43, 1.6, 1.6, .gun) { _, _ in "K" }
        canvas.seam(.gun, onto: [.hand])
        canvas.seam(.hand, onto: [.body, .wing, .head])
        if flash {
            canvas.ellipse(47, 35, 4.5, 4.5, .effect) { nx, ny in nx * nx + ny * ny < 0.35 ? "X" : "x" }
            for (x, y) in [(47, 27), (47, 26), (55, 35), (56, 35), (39, 35), (53, 29), (54, 28), (41, 29), (53, 41), (54, 42)] {
                canvas.set(x, y, "x", .effect)
            }
        }
    }

    /// The meme sunglasses: black pixel lenses with white glints, on a bar back to the ear.
    private static func paintDealWithIt(_ canvas: inout PixelCanvas, hx: Int, hy: Int) {
        canvas.stamp([
            "KKKKKKKKKKKKKKKKK",
            ".....KKKKKK.KKKKK",
            ".....KwKKKK.KwKKK",
            ".....KKwKKK.KKwKK",
            "......KKKK...KKK.",
        ], hx - 6, hy - 4, .face)
    }

    /// A hand on each side of the duck, back of the hand toward you, middle finger up. Pumped on the beat.
    private static func paintFingers(_ canvas: inout PixelCanvas, bodyY: Int, pump: Int) {
        let hand = [
            "....HH....",
            "...HHHh...",
            "...HHHh...",
            "...HHHh...",
            "...HHHh...",
            ".hHHHHHhh.",
            "hHHhHHHhHh",
            "HHHhHHHhHH",
            "HHHHHHHHHh",
            "hHHHHHHHhh",
            ".hHHHHHHh.",
            "..hHHHHh..",
            "..hHHHHh..",
        ]
        canvas.stamp(hand, 0, 27 + bodyY - (pump == 1 ? 3 : 0), .hand)
        canvas.stamp(hand, 38, 29 + bodyY - (pump == 2 ? 3 : 0), .hand)
        canvas.seam(.hand, onto: [.body, .wing, .head, .beak])
    }

    /// A tiny laptop on the floor in front of the duck, screen glowing.
    private static func paintLaptop(_ canvas: inout PixelCanvas) {
        canvas.rect(33, 53, 50, 55, "l", .laptop)
        canvas.rect(33, 55, 50, 55, "e", .laptop)
        for row in 0..<13 {
            let x = 48 + row / 4
            canvas.set(x, 52 - row, "e", .laptop)
            canvas.set(x - 1, 52 - row, row > 1 && row < 12 ? "c" : "e", .laptop)
        }
        canvas.seam(.laptop, onto: [.body, .wing, .leg])
    }

    // MARK: Images

    /// Draws one frame into a new image, `scale` device pixels per art pixel. Faces right.
    static func image(skin: DuckSkin, pose: Pose, scale: Int) -> CGImage? {
        let width = canvasWidth * scale, height = canvasHeight * scale
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        draw(skin: skin, pose: pose, in: context, scale: CGFloat(scale))
        return context.makeImage()
    }

    /// Draws a frame with its bottom left at the context's origin.
    static func draw(skin: DuckSkin, pose: Pose, in context: CGContext, scale: CGFloat) {
        let palette = skin.plumage.palette
        let pixels = paint(skin, pose)
        let height = CGFloat(canvasHeight)
        for (row, line) in pixels.enumerated() {
            for (column, character) in line.enumerated() {
                guard let character, let color = palette[character] else { continue }
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: CGFloat(column) * scale, y: (height - CGFloat(row) - 1) * scale,
                                    width: scale, height: scale))
            }
        }
    }
}
