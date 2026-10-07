import SwiftData
import XCTest
@testable import RestRoutine

@MainActor
final class BackupTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "BackupTests-\(UUID().uuidString)")
    }

    private func seed(_ store: JournalStore) throws {
        try store.saveSleep(SleepDraft(
            start: TestSupport.date(2026, 10, 6, 23), end: TestSupport.date(2026, 10, 7, 7),
            timeZoneIdentifier: "America/Chicago", awakeMinutesText: "30", quality: 3, note: "Sample"))
        try store.saveHabits(HabitDraft(waterText: "0", movementText: "20", windDown: .done),
                             dateKey: "2026-10-07", unit: .milliliters)
    }

    private func backupData(_ store: JournalStore) throws -> Data {
        defaults.waterUnit = .usFluidOunces
        let reminders: [ReminderKind: ReminderSetting] = [
            .morning: ReminderSetting(enabled: true, hour: 8, minute: 15), .evening: .defaults(for: .evening),
        ]
        return try BackupService.encode(BackupService.makeBackup(store: store, defaults: defaults, reminders: reminders))
    }

    func testBackupRoundTripRestoresAllRecords() throws {
        let (_, source) = try TestSupport.inMemoryStore()
        try seed(source)
        let data = try backupData(source)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"format\" : \"com.example.RestRoutine.backup\""))
        XCTAssertTrue(json.contains("\"version\" : 1"))

        let (_, target) = try TestSupport.inMemoryStore()
        try target.saveSleep(SleepDraft(
            start: TestSupport.date(2026, 9, 1, 22), end: TestSupport.date(2026, 9, 2, 6), timeZoneIdentifier: "UTC"))
        let file = try BackupService.validate(data)
        try BackupService.restore(file, into: target.context)

        let sleep = try target.allSleep()
        XCTAssertEqual(sleep.map(\.wakeDateKey), ["2026-10-07"], "restore replaces existing records")
        XCTAssertEqual(sleep.first?.estimatedSleep, 7.5 * 3600)
        XCTAssertEqual(sleep.first?.quality, 3)
        XCTAssertEqual(sleep.first?.note, "Sample")
        let habits = try XCTUnwrap(target.habitDay(dateKey: "2026-10-07"))
        XCTAssertEqual(habits.waterMilliliters, 0)
        XCTAssertEqual(habits.movementMinutes, 20)
        XCTAssertEqual(habits.windDown, .done)
        XCTAssertEqual(file.preferences.waterUnit, "usFluidOunces")
        XCTAssertEqual(file.preferences.morningReminder, ReminderSetting(enabled: true, hour: 8, minute: 15))
    }

    func testInvalidFilesAreRejectedAndLeaveRecordsUnchanged() throws {
        let (_, store) = try TestSupport.inMemoryStore()
        try seed(store)
        let good = try backupData(store)
        var object = try JSONSerialization.jsonObject(with: good) as! [String: Any]

        func mutated(_ change: (inout [String: Any]) -> Void) throws -> Data {
            var copy = object
            change(&copy)
            return try JSONSerialization.data(withJSONObject: copy)
        }

        let cases: [(String, Data, BackupError)] = [
            ("garbage", Data("not json".utf8), .unreadable),
            ("other format", try mutated { $0["format"] = "something.else" }, .notABackup),
            ("future version", try mutated { $0["version"] = 2 }, .unsupportedVersion(2)),
            ("missing field", try mutated { $0.removeValue(forKey: "habitDays") }, .unreadable),
        ]
        for (name, data, expected) in cases {
            XCTAssertThrowsError(try BackupService.validate(data), name) {
                XCTAssertEqual($0 as? BackupError, expected, name)
            }
        }

        var sleep = (object["sleepEntries"] as! [[String: Any]])[0]
        sleep["awakeMinutes"] = 9999
        let badAwake = try mutated { $0["sleepEntries"] = [sleep] }
        XCTAssertThrowsError(try BackupService.validate(badAwake))

        var habit = (object["habitDays"] as! [[String: Any]])[0]
        habit["waterMilliliters"] = -10
        XCTAssertThrowsError(try BackupService.validate(try mutated { $0["habitDays"] = [habit] }))

        let original = (object["sleepEntries"] as! [[String: Any]])[0]
        var twin = original
        twin["id"] = UUID().uuidString
        XCTAssertThrowsError(try BackupService.validate(try mutated { $0["sleepEntries"] = [original, twin] }),
                             "two entries for one wake date")
        object["preferences"] = ["waterUnit": "gallons"]
        XCTAssertThrowsError(try BackupService.validate(try JSONSerialization.data(withJSONObject: object)))

        // Nothing above reached the database.
        XCTAssertEqual(try store.allSleep().count, 1)
        XCTAssertEqual(try store.allSleep().first?.note, "Sample")
        XCTAssertEqual(try store.habitDay(dateKey: "2026-10-07")?.movementMinutes, 20)
    }

    func testRestoredRemindersStayOffWithoutAskingPermission() async throws {
        let scheduler = FakeScheduler(permission: .notDetermined)
        let controller = ReminderController(scheduler: scheduler, defaults: defaults)
        controller.applyRestored([.morning: ReminderSetting(enabled: true, hour: 8, minute: 15)])
        XCTAssertEqual(controller.setting(.morning), ReminderSetting(enabled: false, hour: 8, minute: 15))
        XCTAssertEqual(scheduler.permissionRequests, 0)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }
}
