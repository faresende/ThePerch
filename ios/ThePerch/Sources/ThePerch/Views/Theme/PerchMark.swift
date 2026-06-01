import SwiftUI

enum PerchMark {
    struct Runs: Equatable { let before: String; let marked: String; let after: String }

    /// Split `text` around the first **word-boundary** case-insensitive
    /// occurrence of `phrase`. Boundary-aware so a phrase like "recover"
    /// marks the standalone word and never the "recover" inside "Recovery".
    /// Returns nil when phrase is empty or has no whole-word match
    /// (→ render plain, unmarked).
    static func runs(in text: String, phrase: String) -> Runs? {
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return nil }
        var searchStart = text.startIndex
        while let r = text.range(of: p, options: .caseInsensitive,
                                 range: searchStart..<text.endIndex) {
            let beforeOK = r.lowerBound == text.startIndex
                || !text[text.index(before: r.lowerBound)].isWordCharacter
            let afterOK = r.upperBound == text.endIndex
                || !text[r.upperBound].isWordCharacter
            if beforeOK && afterOK {
                return Runs(before: String(text[text.startIndex..<r.lowerBound]),
                            marked: String(text[r]),
                            after:  String(text[r.upperBound...]))
            }
            searchStart = r.upperBound
        }
        return nil
    }
}

/// Baseline-anchored highlight painted BEHIND a run of text (Stet marker).
/// Stops match tokens.css: paint from 56%→93% of the line box.
/// Not yet wired into the wrapping insight body — that path approximates
/// the mark with an `AttributedString` backgroundColor (full line box).
/// This is the intended band-accurate replacement for single-line marks.
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

private extension Character {
    /// Letters and digits read as "inside a word" for marker boundary tests.
    var isWordCharacter: Bool { isLetter || isNumber }
}
