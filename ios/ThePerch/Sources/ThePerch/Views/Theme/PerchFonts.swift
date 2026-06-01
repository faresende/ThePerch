import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

/// Bundled type families for the time-of-day system. Registered at launch
/// from Asset Catalog Data Sets via CoreText, so the font files need no
/// Info.plist/UIAppFonts entries (this source file is registered in the
/// pbxproj as usual). Reference families by the names CoreText reports.
enum PerchFonts {
    /// Asset name → expected family name (verified in PerchFontsTests/log).
    private static let assets = ["Fraunces", "FrauncesItalic", "Inter", "Archivo", "JetBrainsMono"]

    /// Call once, early, before any view renders (app init).
    static func registerAll() {
        for asset in assets {
            guard let data = NSDataAsset(name: asset)?.data else {
                assertionFailure("Missing font Data Set: \(asset)"); continue
            }
            guard let provider = CGDataProvider(data: data as CFData),
                  let font = CGFont(provider) else { continue }
            var err: Unmanaged<CFError>?
            if !CTFontManagerRegisterGraphicsFont(font, &err) {
                // Already-registered is fine on hot reload; log others.
                if let e = err?.takeRetainedValue() { print("Font register \(asset): \(e)") }
            }
        }
    }

    // Family names CoreText registers (confirm via Task 1 Step 2).
    static let frauncesFamily = "Fraunces"
    static let interFamily     = "Inter"
    static let archivoFamily   = "Archivo"
    static let monoFamily      = "JetBrains Mono"

    // PostScript names of the bundled Fraunces masters (the default instance
    // is 9pt **Black/900** — the heaviest weight), used to instance the
    // variable `wght`/`opsz` axes directly. See `frauncesAxis`.
    private static let frauncesUprightPS = "Fraunces-9ptBlack"
    private static let frauncesItalicPS  = "Fraunces-9ptBlackItalic"

    // Variable-font axis identifiers (4-char tags as FourCharCodes).
    private static let wghtAxis = NSNumber(value: 0x77676874) // 'wght'
    private static let opszAxis = NSNumber(value: 0x6F70737A) // 'opsz'

    /// Build a Fraunces `Font` at an explicit variable-font weight.
    ///
    /// The bundled TTF's default instance is Black (900), and SwiftUI's
    /// `.weight()` modifier does **not** drive a CoreText-registered variable
    /// font's `wght` axis — so the weight must be instanced on the axis here,
    /// or every glyph renders at 900 (chunky). `opsz` is pinned to the point
    /// size for proper optical sizing at display sizes.
    static func frauncesAxis(size: CGFloat, wght: CGFloat, italic: Bool) -> Font {
        let psName = italic ? frauncesItalicPS : frauncesUprightPS
        let variations: [NSNumber: NSNumber] = [
            wghtAxis: NSNumber(value: Double(wght)),
            opszAxis: NSNumber(value: Double(size)),
        ]
        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: psName,
            kCTFontVariationAttribute: variations as CFDictionary,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        return Font(ctFont)
    }
}

extension Font {
    /// Fraunces upright (display + tabular figures). The bundled master is
    /// Black/900, so pass `wght` to pick a lighter cut — `.weight()` won't.
    static func fraunces(_ size: CGFloat, wght: CGFloat = 340) -> Font {
        PerchFonts.frauncesAxis(size: size, wght: wght, italic: false)
    }
    /// Fraunces italic — the brand voice (greeting, biochecha, card titles).
    static func frauncesItalic(_ size: CGFloat, wght: CGFloat = 340) -> Font {
        PerchFonts.frauncesAxis(size: size, wght: wght, italic: true)
    }
    /// Inter — running body copy.
    static func inter(_ size: CGFloat) -> Font { .custom(PerchFonts.interFamily, size: size) }
    /// Archivo 700 — uppercase kicker labels (apply .tracking(0.14em*size) + uppercase at the call site).
    static func archivoKicker(_ size: CGFloat) -> Font {
        .custom(PerchFonts.archivoFamily, size: size).weight(.bold)
    }
    /// JetBrains Mono — timestamps + macro figures.
    static func jbMono(_ size: CGFloat) -> Font { .custom(PerchFonts.monoFamily, size: size) }
}
