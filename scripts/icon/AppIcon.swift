import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the app icon and the README's duck line-up from the duck's own pixel art (QuackieChan/Duck/Sprites.swift).
// Run it through scripts/make-icons.sh.

@main
struct AppIconMaker {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            print("usage: appicon <AppIcon.appiconset> <docs/images>")
            exit(1)
        }
        let iconSet = URL(fileURLWithPath: arguments[1])
        let images = URL(fileURLWithPath: arguments[2])
        try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)

        var entries: [String] = []
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try write(icon(pixels: points * scale), to: iconSet.appendingPathComponent(name))
                entries.append("""
                    { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
                """)
            }
        }
        let contents = "{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
        try contents.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

        try write(lineup(), to: images.appendingPathComponent("ducks.png"))
        try writeAnimations(to: images)
        try write(socialPreview(), to: images.appendingPathComponent("social-preview.png"))
        try write(poses(), to: images.appendingPathComponent("poses.png"))
        try write(icon(pixels: 512), to: images.appendingPathComponent("icon.png"))
    }

    /// A pond-blue rounded square with Quackie Chan on it.
    static func icon(pixels: Int) -> CGImage {
        let size = CGFloat(pixels)
        let context = makeContext(width: pixels, height: pixels)
        // macOS icons sit inside a 10% margin.
        let inset = size * 0.1
        let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let path = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)
        context.addPath(path)
        context.clip()
        let colors = [RGB(0x2B3A67).cgColor, RGB(0x1E2238).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
        // A little pond for it to stand in.
        context.setFillColor(RGB(0x3E5A9E).cgColor)
        context.fillEllipse(in: CGRect(x: tile.minX + tile.width * 0.12, y: tile.minY + tile.height * 0.08,
                                       width: tile.width * 0.76, height: tile.height * 0.16))

        let artPixel = max(1, (tile.width * 0.95 / CGFloat(DuckArt.canvasWidth)).rounded(.down))
        let artWidth = artPixel * CGFloat(DuckArt.canvasWidth)
        context.translateBy(x: (size - artWidth) / 2 + artPixel * 6, y: tile.minY + tile.height * 0.04)
        context.setShouldAntialias(false)
        DuckArt.draw(skin: .standard, pose: Pose(), in: context, scale: max(1, artPixel))
        return context.makeImage()!
    }

    /// Every duck in a row, on the README's dark background.
    static func lineup() -> CGImage {
        sheet(DuckSkin.all.enumerated().map { index, skin in
            (skin, Pose(eyes: index % 4 == 1 ? .blink : .open, beakOpen: index % 3 == 2))
        })
    }

    /// One duck doing all the things.
    static func poses() -> CGImage {
        let skin = DuckSkin.with(id: "don")
        return sheet([
            (skin, Pose()),
            (skin, Pose(eyes: .angry, beakOpen: true, wing: .forward, gun: true)),
            (skin, Pose(eyes: .angry, wing: .forward, gun: true, muzzleFlash: true)),
            (skin, Pose(eyes: .happy, legs: .stepA, wing: .up, blush: true)),
            (skin, Pose(eyes: .shocked, beakOpen: true, legs: .dangling, wing: .up)),
            (skin, Pose(lookY: 1, legs: .tucked, wing: .typingA, sweat: true, laptop: true)),
            (skin, Pose(eyes: .blink, bodyY: 3, legs: .tucked)),
            (skin, Pose(eyes: .dizzy, headX: -1, headY: 1)),
            (DuckSkin.with(id: "bill"), Pose(eyes: .happy, beakOpen: true, legs: .stepA, dealWithIt: true, fingers: true, pump: 1)),
            (DuckSkin.standard, Pose(eyes: .angry, beakOpen: true, headX: 3, headY: 6)),
        ])
    }

    static func sheet(_ ducks: [(DuckSkin, Pose)]) -> CGImage {
        let pixel = 4
        let cell = DuckArt.canvasWidth * pixel
        let width = cell * ducks.count + 16 * pixel
        let height = (DuckArt.canvasHeight + 8) * pixel
        let context = makeContext(width: width, height: height)
        context.setFillColor(RGB(0x1E2238).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(false)
        for (index, (skin, pose)) in ducks.enumerated() {
            context.saveGState()
            context.translateBy(x: CGFloat(8 * pixel + index * cell), y: CGFloat(4 * pixel))
            DuckArt.draw(skin: skin, pose: pose, in: context, scale: CGFloat(pixel))
            context.restoreGState()
        }
        return context.makeImage()!
    }

    /// The 1280 × 640 card GitHub shows when the repo is shared: the name, the pitch, and three ducks.
    static func socialPreview() -> CGImage {
        let width = 1280, height = 640
        let context = makeContext(width: width, height: height)
        let colors = [RGB(0x2B3A67).cgColor, RGB(0x1E2238).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: .zero, options: [])
        context.setFillColor(RGB(0x2B3456).cgColor)
        context.fill(CGRect(x: 80, y: 96, width: width - 160, height: 6))

        func text(_ string: String, size: CGFloat, weight: CTFontUIFontType, color: CGColor, at point: CGPoint) {
            let font = CTFontCreateUIFontForLanguage(weight, size, nil)!
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]))
            context.textPosition = point
            CTLineDraw(line, context)
        }
        text("Quackie Chan", size: 96, weight: .emphasizedSystem, color: CGColor(gray: 1, alpha: 1), at: CGPoint(x: 80, y: 470))
        text("A tiny pixel duck that lives on your Mac", size: 38, weight: .system, color: RGB(0xE9DAC0).cgColor, at: CGPoint(x: 84, y: 405))
        text("and keeps you honest.", size: 38, weight: .system, color: RGB(0xE9DAC0).cgColor, at: CGPoint(x: 84, y: 358))
        text("Sees your screen · talks · dances · 100% on-device AI", size: 24, weight: .system,
             color: RGB(0x8E9BC4).cgColor, at: CGPoint(x: 84, y: 300))

        let pixel: CGFloat = 4.6
        let ducks: [(DuckSkin, Pose, CGFloat)] = [
            (DuckSkin.with(id: "don"), Pose(eyes: .angry, wing: .forward, gun: true), 700),
            (DuckSkin.with(id: "bill"), Pose(eyes: .happy, beakOpen: true, legs: .stepA, dealWithIt: true, fingers: true, pump: 1), 975),
        ]
        context.setShouldAntialias(false)
        for (skin, pose, x) in ducks {
            context.saveGState()
            context.translateBy(x: x, y: 100)
            DuckArt.draw(skin: skin, pose: pose, in: context, scale: pixel)
            context.restoreGState()
        }
        return context.makeImage()!
    }

    // MARK: Animated GIFs for the README

    /// One frame: a pose, plus the smooth bounce (art pixels) and lean (degrees) the app adds on top.
    struct Frame {
        var pose: Pose
        var lift: CGFloat = 0
        var tilt: CGFloat = 0
        var flipped = false
    }

    static func writeAnimations(to folder: URL) throws {
        let quackie = DuckSkin.standard, don = DuckSkin.with(id: "don"), bill = DuckSkin.with(id: "bill")
        let beatFrames = 6  // frames per beat at 12 fps ≈ 120 bpm

        // Dancing: step-touch with wings, a bounce on every beat and a lean that swaps sides.
        var dance: [Frame] = []
        for beat in 0..<8 {
            for f in 0..<beatFrames {
                let phase = Double(beat) + Double(f) / Double(beatFrames)
                var pose = Pose(eyes: .happy, beakOpen: f < 3 && beat % 2 == 0, headY: f < 3 ? 1 : 0)
                pose.legs = beat % 2 == 0 ? .stepA : .stepB
                pose.wing = beat % 2 == 0 ? .up : .forward
                dance.append(Frame(pose: pose, lift: 3.5 * abs(sin(.pi * phase)), tilt: 7 * sin(.pi * phase), flipped: beat >= 6))
            }
        }
        try gif(dance, skin: quackie, bubble: "Oh this one's good.", to: folder.appendingPathComponent("dance.gif"))

        // Bananas: shades on, fingers up, losing it.
        var bananas: [Frame] = []
        for beat in 0..<8 {
            for f in 0..<beatFrames {
                let phase = Double(beat) + Double(f) / Double(beatFrames)
                let half = f < 3
                var pose = Pose(eyes: .happy, beakOpen: half, headX: half ? 1 : -1, headY: half ? 2 : 0, bodyY: half ? 1 : 0)
                pose.legs = beat % 2 == 0 ? .stepA : .stepB
                pose.dealWithIt = true
                pose.fingers = true
                pose.pump = beat % 2 == 0 ? 1 : 2
                bananas.append(Frame(pose: pose, lift: 6 * abs(sin(.pi * phase)), tilt: 12 * sin(.pi * phase), flipped: (beat / 2) % 2 == 1))
            }
        }
        try gif(bananas, skin: bill, bubble: "THIS IS MY JAM", to: folder.appendingPathComponent("bananas.gif"))

        // The gun: aim, hold it, BANG.
        var gun: [Frame] = []
        for f in 0..<30 {
            var pose = Pose(eyes: .angry, wing: .forward, gun: true)
            pose.beakOpen = f > 4 && f < 14 && f % 2 == 0
            pose.muzzleFlash = f == 22 || f == 23
            if pose.muzzleFlash { pose.headX = -1 }
            gun.append(Frame(pose: pose, tilt: pose.muzzleFlash ? -8 : 0))
        }
        try gif(gun, skin: don, bubble: "Or else.", alarm: true, to: folder.appendingPathComponent("gun.gif"))

        // Typing along with you, getting frantic.
        var typing: [Frame] = []
        for f in 0..<24 {
            var pose = Pose(lookX: 1, lookY: 1, bodyY: 3, legs: .tucked, laptop: true)
            pose.wing = f % 2 == 0 ? .typingA : .typingB
            pose.sweat = f >= 12
            if f >= 12 { pose.eyes = .angry }
            typing.append(Frame(pose: pose))
        }
        try gif(typing, skin: quackie, bubble: "CALM DOWN, SHAKESPEARE.", to: folder.appendingPathComponent("typing.gif"))

        // Flying: flapping, wobbling.
        var flying: [Frame] = []
        for f in 0..<16 {
            let pose = Pose(lookX: 1, bodyY: 0, legs: .tucked, wing: f % 2 == 0 ? .up : .rest)
            flying.append(Frame(pose: pose, lift: 4 + 3 * sin(Double(f) / 16 * 2 * .pi), tilt: 6 * sin(Double(f) * 1.3)))
        }
        try gif(flying, skin: quackie, bubble: "Duck. Airlines.", to: folder.appendingPathComponent("fly.gif"))

        // Pecking a tab closed.
        var peck: [Frame] = []
        for f in 0..<16 {
            let down = (f / 2) % 2 == 0
            peck.append(Frame(pose: Pose(eyes: .angry, beakOpen: !down, headX: down ? 3 : 1, headY: down ? 6 : 2)))
        }
        try gif(peck, skin: quackie, bubble: "No Instagram for you!", to: folder.appendingPathComponent("peck.gif"))

        // Napping while you're away.
        var nap: [Frame] = []
        for f in 0..<20 {
            nap.append(Frame(pose: Pose(eyes: .blink, headY: 1, bodyY: 3 + (f / 10), legs: .tucked)))
        }
        try gif(nap, skin: DuckSkin.with(id: "merlin"), bubble: "zzz…", to: folder.appendingPathComponent("nap.gif"))

        // Sat down when told, and staying sat.
        var sit: [Frame] = []
        for f in 0..<24 {
            sit.append(Frame(pose: Pose(eyes: f == 9 || f == 10 ? .blink : .open, bodyY: 3 + (f / 12), legs: .tucked)))
        }
        try gif(sit, skin: quackie, bubble: "Sat. Staying. Very obedient.", to: folder.appendingPathComponent("sit.gif"))

        // Nobody pets it, so it drinks: a swig, a sway, a hiccup.
        var drunk: [Frame] = []
        for f in 0..<36 {
            let swig = f >= 10 && f < 22
            var pose = Pose(eyes: swig ? .happy : .drunk, headY: swig ? -1 : 0, wing: .forward)
            pose.beer = swig ? 2 : 1
            pose.flushed = true
            pose.monkHair = 1
            let hic = f == 28 || f == 29
            drunk.append(Frame(pose: pose, lift: hic ? 2 : 0, tilt: swig ? -6 : 5 * sin(Double(f) / 36 * 2 * .pi)))
        }
        try gif(drunk, skin: quackie, bubble: "You never pet me anymore. *hic*", to: folder.appendingPathComponent("drunk.gif"))

        // Completely wasted, and you tried to pet it.
        var wasted: [Frame] = []
        for f in 0..<24 {
            var pose = Pose(eyes: .angry, beakOpen: true, wing: .forward)
            pose.machineGun = true
            pose.flushed = true
            pose.monkHair = 2
            pose.muzzleFlash = f >= 6 && f % 2 == 0
            if pose.muzzleFlash { pose.headX = -1 }
            wasted.append(Frame(pose: pose, tilt: f >= 6 ? (f % 2 == 0 ? -4 : -2) : 0))
        }
        try gif(wasted, skin: DuckSkin.with(id: "don"), bubble: "NO PETS. NO PETS!", alarm: true,
                to: folder.appendingPathComponent("wasted.gif"))
    }

    /// Writes frames as a looping GIF on a dark rounded tile, with a speech bubble above the duck.
    static func gif(_ frames: [Frame], skin: DuckSkin, bubble: String?, alarm: Bool = false, to url: URL) throws {
        let pixel: CGFloat = 4
        let width = 360, height = 360
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12]] as CFDictionary
        for frame in frames {
            let context = makeContext(width: width, height: height)
            context.setFillColor(RGB(0x1E2238).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // A little ground line.
            context.setFillColor(RGB(0x2B3456).cgColor)
            context.fill(CGRect(x: 40, y: 36, width: width - 80, height: 4))
            if let bubble { drawBubble(bubble, alarm: alarm, in: context, width: CGFloat(width), top: CGFloat(height) - 16) }

            let art = CGFloat(DuckArt.canvasWidth) * pixel
            context.saveGState()
            context.setShouldAntialias(false)
            context.interpolationQuality = .none
            // Feet sit on the ground line; lean and bounce happen around the feet, like in the app.
            let feet = CGPoint(x: CGFloat(width) / 2, y: 40 + frame.lift * pixel)
            context.translateBy(x: feet.x, y: feet.y)
            context.rotate(by: -frame.tilt * .pi / 180 * (frame.flipped ? -1 : 1))
            if frame.flipped { context.scaleBy(x: -1, y: 1) }
            context.translateBy(x: -art / 2 + 6 * pixel, y: -2 * pixel)
            DuckArt.draw(skin: skin, pose: frame.pose, in: context, scale: pixel)
            context.restoreGState()
            CGImageDestinationAddImage(destination, context.makeImage()!, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// The duck's speech bubble: dark, rounded, a light border and a little tail.
    static func drawBubble(_ text: String, alarm: Bool, in context: CGContext, width: CGFloat, top: CGFloat) {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 17, nil)!
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let textWidth = min(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)), width - 60)
        let box = CGRect(x: (width - textWidth) / 2 - 16, y: top - 46, width: textWidth + 32, height: 40)
        let path = CGMutablePath()
        path.addRoundedRect(in: box, cornerWidth: 12, cornerHeight: 12)
        path.move(to: CGPoint(x: width / 2 - 9, y: box.minY))
        path.addLine(to: CGPoint(x: width / 2, y: box.minY - 10))
        path.addLine(to: CGPoint(x: width / 2 + 9, y: box.minY))
        context.saveGState()
        context.setShouldAntialias(true)
        context.addPath(path)
        context.setFillColor(RGB(0x2B2622).cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(alarm ? RGB(0xE0453A).cgColor : RGB(0xCCB899).cgColor)
        context.setLineWidth(3)
        context.strokePath()
        context.textPosition = CGPoint(x: box.minX + 16, y: box.minY + 13)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    static func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
