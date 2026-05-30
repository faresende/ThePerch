import SwiftUI

enum PerchMark {
    struct Runs: Equatable { let before: String; let marked: String; let after: String }

    /// Split `text` around the first case-insensitive occurrence of `phrase`.
    /// Returns nil when phrase is empty or not found (→ render plain, unmarked).
    static func runs(in text: String, phrase: String) -> Runs? {
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, let r = text.range(of: p, options: .caseInsensitive) else { return nil }
        return Runs(before: String(text[text.startIndex..<r.lowerBound]),
                    marked: String(text[r]),
                    after:  String(text[r.upperBound...]))
    }
}

/// Baseline-anchored highlight painted BEHIND a run of text (Stet marker).
/// Stops match tokens.css: paint from 56%→93% of the line box.
struct PerchMarkBackground: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            color
                .frame(height: h * (0.93 - 0.56))
                .offset(y: h * 0.56 - h * 0.5 + (h * (0.93 - 0.56)) / 2)
        }
    }
}

extension View {
    /// Apply the marker highlight behind this text run.
    func perchMark(_ color: Color) -> some View {
        background(alignment: .center) { PerchMarkBackground(color: color) }
    }
}
