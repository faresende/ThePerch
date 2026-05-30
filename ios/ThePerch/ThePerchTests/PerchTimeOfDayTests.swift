import Testing
@testable import ThePerch

@Suite("PerchTimeOfDay schedule (handoff boundaries)")
struct PerchTimeOfDayTests {
    @Test("11:00 is afternoon, not morning", arguments: [
        (5, PerchTimeOfDay.sunrise), (10, .sunrise),
        (11, .midday), (16, .midday),
        (17, .dusk), (21, .dusk),
        (22, .night), (4, .night), (0, .night)
    ])
    func bracket(hour: Int, expected: PerchTimeOfDay) {
        #expect(PerchTimeOfDay.bracket(forHour: hour) == expected)
    }
}
