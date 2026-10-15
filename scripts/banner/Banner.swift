import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the 1600 × 400 banner (for Buy Me a Coffee, social cards and the like) from the duck's own pixel art.
// Run it through scripts/make-banner.sh.

@main
struct BannerMaker {
    static let width = 1600, height = 400

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            print("usage: banner <Fredoka.ttf> <banner.png>")
            exit(1)
        }
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, .process, nil)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        background(context)
        words(context)
        ground(context)
        ducks(context)
        try write(context.makeImage()!, to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// Night sky: deep blue at the top fading darker toward the ground, with a soft glow behind the ducks.
    static func background(_ context: CGContext) {
        let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                             colors: [color(0x2D3A68), color(0x1C2140)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(sky, start: CGPoint(x: 0, y: height), end: .zero, options: [])
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0x4A5A9A, 0.35), color(0x4A5A9A, 0)] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(glow, startCenter: CGPoint(x: 1230, y: 170), startRadius: 0,
                                   endCenter: CGPoint(x: 1230, y: 170), endRadius: 380, options: [])
    }

    static func font(_ size: CGFloat, weight: CGFloat) -> CTFont {
        let base = CTFontCreateWithName("Fredoka" as CFString, size, nil)
        // Fredoka is a variable font: pick the weight on its "wght" axis.
        let axis = NSNumber(value: 0x7767_6874)  // 'wght'
        let descriptor = CTFontDescriptorCreateCopyWithVariation(CTFontCopyFontDescriptor(base), axis, weight)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// Draws a line of text with its baseline `top` points down from the top edge.
    static func text(_ string: String, _ font: CTFont, _ fill: CGColor, x: CGFloat, top: CGFloat, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: CGFloat(height) - top)
        CTLineDraw(line, context)
    }

    static func words(_ context: CGContext) {
        let left: CGFloat = 96
        text("Quackie Chan", font(92, weight: 650), color(0xFFFFFF), x: left, top: 128, in: context)
        let cream = color(0xF3E2C0)
        text("A tiny pixel duck that lives on your Mac", font(38, weight: 450), cream, x: left, top: 192, in: context)
        text("and keeps you honest.", font(38, weight: 450), cream, x: left, top: 238, in: context)
        text("Sees your screen · talks · dances · 100% on-device AI", font(24, weight: 450), color(0x8E9BC8),
             x: left, top: 292, in: context)
    }

    /// The floor the ducks stand on.
    static let floor: CGFloat = 346

    static func ground(_ context: CGContext) {
        context.setFillColor(color(0x37426E))
        context.fill(CGRect(x: 96, y: CGFloat(height) - floor - 2, width: CGFloat(width) - 192, height: 4))
    }

    static func ducks(_ context: CGContext) {
        let scale: CGFloat = 5
        // The canvas's feet sit on row 56 (counting from the top of its 58 rows).
        let bottom = CGFloat(height) - floor - 2 * scale
        let cast: [(DuckSkin, Pose, CGFloat)] = [
            (DuckSkin.with(id: "don"), Pose(eyes: .angry, wing: .forward, gun: true), 945),
            (DuckSkin.with(id: "bill"), Pose(eyes: .happy, beakOpen: true, legs: .stepA, dealWithIt: true, fingers: true, pump: 1), 1235),
        ]
        for (skin, pose, x) in cast {
            context.saveGState()
            context.translateBy(x: x, y: bottom)
            DuckArt.draw(skin: skin, pose: pose, in: context, scale: scale)
            context.restoreGState()
        }
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
