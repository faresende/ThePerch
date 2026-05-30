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
}

extension Font {
    /// Fraunces upright (display + tabular figures). Weight via .fontWeight().
    static func fraunces(_ size: CGFloat) -> Font { .custom(PerchFonts.frauncesFamily, size: size) }
    /// Fraunces italic — the brand voice (greeting, biochecha, card titles).
    static func frauncesItalic(_ size: CGFloat) -> Font {
        .custom(PerchFonts.frauncesFamily, size: size).italic()
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
