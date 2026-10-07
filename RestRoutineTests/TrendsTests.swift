import XCTest
@testable import RestRoutine

@MainActor
final class TrendsTests: XCTestCase {
    func testMissingDaysAreGapsAndExcludedFromAverages() {
        let days = DayKey(rawValue: "2026-10-07")!.trailing(7)
        let summary = Trends.summarize(days: days, values: ["2026-10-07": 8, "2026-10-05": 6])
        XCTAssertEqual(summary.totalDays, 7)
        XCTAssertEqual(summary.loggedCount, 2)
        XCTAssertEqual(summary.average, 7)
        XCTAssertEqual(summary.loggedText, "2 of 7 days logged")
        XCTAssertEqual(summary.points.filter { $0.value == nil }.count, 5)
        XCTAssertNil(Trends.summarize(days: days, values: [:]).average)
    }

    func testRecordedZeroCountsButMissingDoesNot() throws {
        let (_, store) = try TestSupport.inMemoryStore()
        try store.saveHabits(HabitDraft(waterText: "0"), dateKey: "2026-10-06", unit: .milliliters)
        try store.saveHabits(HabitDraft(waterText: "1000", windDown: .notDone), dateKey: "2026-10-07", unit: .milliliters)
        let days = DayKey(rawValue: "2026-10-07")!.trailing(7)
        let summaries = Trends.summaries(days: days, sleep: [], habits: try store.allHabitDays())
        XCTAssertEqual(summaries[.water]?.loggedCount, 2)
        XCTAssertEqual(summaries[.water]?.average, 500)
        XCTAssertEqual(summaries[.windDown]?.loggedCount, 1)
        XCTAssertEqual(summaries[.movement]?.loggedCount, 0)
    }

    func testEditingAndDeletingUpdateSummaries() throws {
        let (_, store) = try TestSupport.inMemoryStore()
        let days = DayKey(rawValue: "2026-10-07")!.trailing(7)
        let entry = try store.saveSleep(SleepDraft(
            start: TestSupport.date(2026, 10, 6, 23), end: TestSupport.date(2026, 10, 7, 7),
            timeZoneIdentifier: "America/Chicago"))
        try store.saveSleep(SleepDraft(
            start: TestSupport.date(2026, 10, 4, 22), end: TestSupport.date(2026, 10, 5, 6),
            timeZoneIdentifier: "America/Chicago", awakeMinutesText: "60"))
        var s = Trends.summaries(days: days, sleep: try store.allSleep(), habits: [])
        XCTAssertEqual(s[.timeInBed]?.loggedCount, 2)
        XCTAssertEqual(s[.estimatedSleep]?.loggedCount, 1, "only entries with awake minutes have estimates")

        var edit = SleepDraft(entry: entry)
        edit.awakeMinutesText = "30"
        try store.saveSleep(edit, editing: entry)
        s = Trends.summaries(days: days, sleep: try store.allSleep(), habits: [])
        XCTAssertEqual(s[.estimatedSleep]?.loggedCount, 2)
        XCTAssertEqual(s[.estimatedSleep]?.average, (7.5 * 3600 + 7 * 3600) / 2)

        try store.deleteSleep(entry)
        s = Trends.summaries(days: days, sleep: try store.allSleep(), habits: [])
        XCTAssertEqual(s[.timeInBed]?.loggedCount, 1)
        XCTAssertEqual(s[.timeInBed]?.average, 8 * 3600)
    }
}
