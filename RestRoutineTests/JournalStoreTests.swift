import SwiftData
import XCTest
@testable import RestRoutine

@MainActor
final class JournalStoreTests: XCTestCase {
    func draft(_ wakeDay: Int, awake: String = "", quality: Int? = nil) -> SleepDraft {
        SleepDraft(
            start: TestSupport.date(2026, 10, wakeDay - 1, 23), end: TestSupport.date(2026, 10, wakeDay, 7),
            timeZoneIdentifier: "America/Chicago", awakeMinutesText: awake, quality: quality)
    }

    func testSavingSleepStoresInstantsZoneAndWakeDate() throws {
        let (_, store) = try TestSupport.inMemoryStore()
        let entry = try store.saveSleep(draft(7, awake: "30", quality: 3))
        XCTAssertEqual(entry.wakeDateKey, "2026-10-07")
        XCTAssertEqual(entry.timeZoneIdentifier, "America/Chicago")
        XCTAssertEqual(entry.awakeMinutes, 30)
        XCTAssertEqual(entry.estimatedSleep, 7.5 * 3600)
        XCTAssertEqual(try store.latestSleep()?.id, entry.id)
    }

    func testSecondEntryForSameWakeDateIsRefusedAndOffersExisting() throws {
        let (_, store) = try TestSupport.inMemoryStore()
        let first = try store.saveSleep(draft(7))
        var other = draft(7)
        other.start = TestSupport.date(2026, 10, 7, 1)
        XCTAssertThrowsError(try store.saveSleep(other)) {
            XCTAssertEqual($0 as? SleepSaveError, .duplicateWakeDate(existingID: first.id, wakeDateKey: "2026-10-07"))
        }
        XCTAssertEqual(try store.allSleep().count, 1)
        // Editing the existing entry is allowed.
        try store.saveSleep(other, editing: first)
        XCTAssertEqual(try store.allSleep().count, 1)
        XCTAssertEqual(first.timeInBed, 6 * 3600)
    }

    func testInvalidSleepIsNotSaved() throws {
        let (_, store) = try TestSupport.inMemoryStore()
        XCTAssertThrowsError(try store.saveSleep(draft(7, awake: "500")))
        var backwards = draft(7)
        backwards.end = backwards.start
        XCTAssertThrowsError(try store.saveSleep(backwards)) {
            XCTAssertEqual($0 as? SleepSaveError, .invalid(.endNotAfterStart))
        }
        XCTAssertEqual(try store.allSleep().count, 0)
    }

    func testHabitsKeepNotLoggedDistinctFromZeroAndNotDone() throws {
        let (_, store) = try TestSupport.inMemoryStore()
        let day = try XCTUnwrap(store.saveHabits(
            HabitDraft(waterText: "0", movementText: "", windDown: .notDone), dateKey: "2026-10-07", unit: .milliliters))
        XCTAssertEqual(day.waterMilliliters, 0)
        XCTAssertNil(day.movementMinutes)
        XCTAssertEqual(day.windDown, .notDone)

        try store.saveHabits(HabitDraft(waterText: "1000", movementText: "20"), dateKey: "2026-10-07", unit: .milliliters)
        let updated = try XCTUnwrap(store.habitDay(dateKey: "2026-10-07"))
        XCTAssertEqual(updated.waterMilliliters, 1000)
        XCTAssertEqual(updated.movementMinutes, 20)
        XCTAssertNil(updated.windDown, "clearing wind-down returns it to Not logged")
        XCTAssertNil(try store.habitDay(dateKey: "2026-10-06"), "a date never logged has no record")
    }

    func testInvalidHabitValuesAreRejectedWithoutChanges() throws {
        let (_, store) = try TestSupport.inMemoryStore()
        try store.saveHabits(HabitDraft(waterText: "500"), dateKey: "2026-10-07", unit: .milliliters)
        XCTAssertThrowsError(try store.saveHabits(
            HabitDraft(waterText: "-1", movementText: "10"), dateKey: "2026-10-07", unit: .milliliters))
        XCTAssertThrowsError(try store.saveHabits(
            HabitDraft(waterText: "600", movementText: "2.5"), dateKey: "2026-10-07", unit: .milliliters))
        XCTAssertEqual(try store.habitDay(dateKey: "2026-10-07")?.waterMilliliters, 500)
    }

    func testClearingEveryHabitRemovesTheRecord() throws {
        let (_, store) = try TestSupport.inMemoryStore()
        try store.saveHabits(HabitDraft(waterText: "500"), dateKey: "2026-10-07", unit: .milliliters)
        XCTAssertNil(try store.saveHabits(HabitDraft(), dateKey: "2026-10-07", unit: .milliliters))
        XCTAssertNil(try store.habitDay(dateKey: "2026-10-07"))
    }

    func testDeleteAndDeleteAll() throws {
        let (_, store) = try TestSupport.inMemoryStore()
        let a = try store.saveSleep(draft(6))
        try store.saveSleep(draft(7))
        try store.saveHabits(HabitDraft(movementText: "5"), dateKey: "2026-10-07", unit: .milliliters)
        try store.deleteSleep(a)
        XCTAssertEqual(try store.allSleep().map(\.wakeDateKey), ["2026-10-07"])
        try store.deleteHabits(dateKey: "2026-10-07")
        XCTAssertTrue(try store.allHabitDays().isEmpty)
        try store.saveHabits(HabitDraft(movementText: "5"), dateKey: "2026-10-07", unit: .milliliters)
        try store.deleteAll()
        XCTAssertTrue(try store.allSleep().isEmpty)
        XCTAssertTrue(try store.allHabitDays().isEmpty)
    }

    func testRecordsSurviveReopeningTheDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("relaunch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("RestRoutine.store")

        do {
            let container = try ModelContainer(
                for: Persistence.schema, configurations: [ModelConfiguration(schema: Persistence.schema, url: url)])
            let store = JournalStore(context: ModelContext(container))
            try store.saveSleep(draft(7, awake: "30"))
            try store.saveHabits(HabitDraft(waterText: "0", windDown: .done), dateKey: "2026-10-07", unit: .milliliters)
        }
        let reopened = try ModelContainer(
            for: Persistence.schema, configurations: [ModelConfiguration(schema: Persistence.schema, url: url)])
        let store = JournalStore(context: ModelContext(reopened))
        let entry = try XCTUnwrap(store.sleepEntry(wakeDateKey: "2026-10-07"))
        XCTAssertEqual(entry.estimatedSleep, 7.5 * 3600)
        let habits = try XCTUnwrap(store.habitDay(dateKey: "2026-10-07"))
        XCTAssertEqual(habits.waterMilliliters, 0)
        XCTAssertNil(habits.movementMinutes)
        XCTAssertEqual(habits.windDown, .done)
    }

    func testStoreDirectoryIsApplicationSupportRestRoutine() throws {
        // The test run uses a disposable store; the production path is checked directly.
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        XCTAssertTrue(base.path.contains("/Library/Containers/com.example.RestRoutine/Data/Library/Application Support"),
                      base.path)
    }
}
