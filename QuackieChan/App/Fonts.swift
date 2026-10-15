import CoreText
import Foundation

/// Fredoka ships inside the app (SIL Open Font License, see Fonts/OFL-Fredoka.txt); this makes it usable.
enum Fonts {
    static let display = "Fredoka"

    static func registerBundled() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }
}
