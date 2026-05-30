import Testing
@testable import ThePerch

@Suite("Marker phrase splitting + decode")
struct PerchMarkTests {
    @Test("splits body into [before, marked, after] on first match")
    func splits() throws {
        let r = try #require(PerchMark.runs(in: "Unless you're going full rabbit, get on that before dinner.",
                                             phrase: "get on that"))
        #expect(r.before == "Unless you're going full rabbit, ")
        #expect(r.marked == "get on that")
        #expect(r.after == " before dinner.")
    }
    @Test("returns nil when phrase absent or empty → render plain")
    func absent() {
        #expect(PerchMark.runs(in: "All quiet.", phrase: "nope") == nil)
        #expect(PerchMark.runs(in: "All quiet.", phrase: "") == nil)
    }
    @Test("skips a sub-word match and marks the standalone word instead")
    func wordBoundaryPrefersStandalone() throws {
        let r = try #require(PerchMark.runs(in: "Recovery means recover today.", phrase: "recover"))
        #expect(r.before == "Recovery means ")
        #expect(r.marked == "recover")
        #expect(r.after == " today.")
    }
    @Test("returns nil when the phrase only appears inside a larger word")
    func wordBoundarySubwordOnlyIsNil() {
        #expect(PerchMark.runs(in: "Recovery mode engaged.", phrase: "recover") == nil)
    }
    @Test("decodes marked_phrase from insight data JSON")
    func decode() throws {
        let json = #"{"marked_phrase":"call it a night","slot":"evening"}"#.data(using: .utf8)!
        let insight = Insight.preview(body: "…so call it a night — tomorrow opens quiet.",
                                      dataRaw: json)
        #expect(insight.markedPhrase == "call it a night")
    }
}
