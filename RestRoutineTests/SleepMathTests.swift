import XCTest
@testable import RestRoutine

final class SleepMathTests: XCTestCase {
    let zone = TestSupport.chicago

    func testCrossMidnightEntryIsEightHoursInBed() {
        let start = TestSupport.date(2026, 10, 6, 23)
        let end = TestSupport.date(2026, 10, 7, 7)
        XCTAssertEqual(SleepMath.timeInBed(start: start, end: end), 8 * 3600)
        XCTAssertEqual(DurationText.format(SleepMath.timeInBed(start: start, end: end)), "8h")
    }

    func testThirtyAwakeMinutesGivesSevenAndAHalfHours() {
        let start = TestSupport.date(2026, 10, 6, 23)
        let end = TestSupport.date(2026, 10, 7, 7)
        let estimate = SleepMath.estimatedSleep(start: start, end: end, awakeMinutes: 30)
        XCTAssertEqual(estimate, 7.5 * 3600)
        XCTAssertEqual(DurationText.format(estimate!), "7h 30m")
    }

    func testBlankAwakeMinutesGivesNoEstimate() throws {
        let start = TestSupport.date(2026, 10, 6, 23)
        let end = TestSupport.date(2026, 10, 7, 7)
        XCTAssertNil(try SleepMath.parseAwakeMinutes("  "))
        XCTAssertNil(SleepMath.estimatedSleep(start: start, end: end, awakeMinutes: nil))
        let entry = SleepEntry(start: start, end: end, timeZoneIdentifier: zone.identifier)
        XCTAssertNil(entry.estimatedSleep)
        XCTAssertEqual(entry.timeInBed, 8 * 3600)
    }

    func testSpringForwardNightIsSevenElapsedHours() {
        // US daylight saving starts 2026-03-08 at 2:00 AM; 11 PM to 7 AM is only 7 real hours.
        let start = TestSupport.date(2026, 3, 7, 23)
        let end = TestSupport.date(2026, 3, 8, 7)
        XCTAssertEqual(SleepMath.timeInBed(start: start, end: end), 7 * 3600)
    }

    func testFallBackNightIsNineElapsedHours() {
        // US daylight saving ends 2026-11-01 at 2:00 AM; 11 PM to 7 AM is 9 real hours.
        let start = TestSupport.date(2026, 10, 31, 23)
        let end = TestSupport.date(2026, 11, 1, 7)
        XCTAssertEqual(SleepMath.timeInBed(start: start, end: end), 9 * 3600)
        XCTAssertEqual(SleepMath.estimatedSleep(start: start, end: end, awakeMinutes: 30), 8.5 * 3600)
    }

    func testWakeDateUsesCapturedTimeZone() {
        let end = TestSupport.date(2026, 10, 7, 7)
        XCTAssertEqual(SleepMath.wakeDateKey(end: end, timeZoneIdentifier: "America/Chicago"), "2026-10-07")
        // 12:30 AM in Chicago is still the evening before in Los Angeles.
        let lateEnd = TestSupport.date(2026, 10, 7, 0, 30)
        XCTAssertEqual(SleepMath.wakeDateKey(end: lateEnd, timeZoneIdentifier: "America/Chicago"), "2026-10-07")
        XCTAssertEqual(SleepMath.wakeDateKey(end: lateEnd, timeZoneIdentifier: "America/Los_Angeles"), "2026-10-06")
    }

    func testRejectsEndNotAfterStart() {
        let start = TestSupport.date(2026, 10, 7, 7)
        XCTAssertThrowsError(try SleepMath.validate(start: start, end: start, awakeMinutes: nil, quality: nil)) {
            XCTAssertEqual($0 as? SleepValidationError, .endNotAfterStart)
        }
        XCTAssertThrowsError(try SleepMath.validate(
            start: start, end: start.addingTimeInterval(-60), awakeMinutes: nil, quality: nil))
    }

    func testRejectsAwakeMinutesOutsideInterval() throws {
        let start = TestSupport.date(2026, 10, 6, 23)
        let end = TestSupport.date(2026, 10, 7, 7)
        XCTAssertNoThrow(try SleepMath.validate(start: start, end: end, awakeMinutes: 0, quality: nil))
        XCTAssertNoThrow(try SleepMath.validate(start: start, end: end, awakeMinutes: 480, quality: nil))
        XCTAssertThrowsError(try SleepMath.validate(start: start, end: end, awakeMinutes: 481, quality: nil)) {
            XCTAssertEqual($0 as? SleepValidationError, .awakeMinutesOutOfRange(maximum: 480))
        }
        XCTAssertThrowsError(try SleepMath.validate(start: start, end: end, awakeMinutes: -1, quality: nil))
        XCTAssertThrowsError(try SleepMath.parseAwakeMinutes("12.5"))
        XCTAssertThrowsError(try SleepMath.parseAwakeMinutes("ten"))
        XCTAssertThrowsError(try SleepMath.validate(start: start, end: end, awakeMinutes: nil, quality: 6))
    }

    func testDurationFormatting() {
        XCTAssertEqual(DurationText.format(45 * 60), "45m")
        XCTAssertEqual(DurationText.format(8 * 3600), "8h")
        XCTAssertEqual(DurationText.format(7 * 3600 + 5 * 60), "7h 5m")
    }

    func testDayKeyArithmetic() {
        let key = DayKey(rawValue: "2026-03-01")!
        XCTAssertEqual(key.adding(days: -1).rawValue, "2026-02-28")
        XCTAssertEqual(key.trailing(3).map(\.rawValue), ["2026-02-27", "2026-02-28", "2026-03-01"])
        XCTAssertNil(DayKey(rawValue: "2026-13-01"))
        XCTAssertNil(DayKey(rawValue: "garbage"))
    }
}
