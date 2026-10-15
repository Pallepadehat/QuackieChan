import CoreGraphics
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
