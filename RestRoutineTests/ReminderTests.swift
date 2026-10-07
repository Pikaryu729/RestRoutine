import XCTest
@testable import RestRoutine

final class FakeScheduler: NotificationScheduling {
    var currentPermission: NotificationPermission
    var grant: Bool
    var permissionRequests = 0
    var scheduled: [String: (title: String, body: String, hour: Int, minute: Int)] = [:]
    var removed: [String] = []

    init(permission: NotificationPermission, grant: Bool = true) {
        currentPermission = permission
        self.grant = grant
    }

    func permission() async -> NotificationPermission { currentPermission }

    func requestPermission() async -> Bool {
        permissionRequests += 1
        currentPermission = grant ? .allowed : .denied
        return grant
    }

    func schedule(identifier: String, title: String, body: String, hour: Int, minute: Int) async throws {
        scheduled[identifier] = (title, body, hour, minute)
    }

    func removePending(identifiers: [String]) {
        removed += identifiers
        for id in identifiers { scheduled.removeValue(forKey: id) }
    }
}

@MainActor
final class ReminderTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "ReminderTests-\(UUID().uuidString)")
    }

    func testRemindersStartOffWithSuggestedTimesAndNoPermissionRequest() {
        let scheduler = FakeScheduler(permission: .notDetermined)
        let controller = ReminderController(scheduler: scheduler, defaults: defaults)
        XCTAssertEqual(controller.setting(.morning), ReminderSetting(enabled: false, hour: 9, minute: 0))
        XCTAssertEqual(controller.setting(.evening), ReminderSetting(enabled: false, hour: 22, minute: 0))
        XCTAssertEqual(scheduler.permissionRequests, 0)
    }

    func testEnablingAsksOnceAndSchedulesGenericReminder() async {
        let scheduler = FakeScheduler(permission: .notDetermined, grant: true)
        let controller = ReminderController(scheduler: scheduler, defaults: defaults)
        await controller.setEnabled(.morning, true)
        XCTAssertEqual(scheduler.permissionRequests, 1)
        XCTAssertTrue(controller.setting(.morning).enabled)
        let request = scheduler.scheduled[ReminderKind.morning.identifier]
        XCTAssertEqual(request?.hour, 9)
        XCTAssertEqual(request?.minute, 0)
        XCTAssertEqual(request?.body, "Time to log last night's sleep.")
        XCTAssertNil(scheduler.scheduled[ReminderKind.evening.identifier], "reminders are independent")
        XCTAssertNil(request?.body.rangeOfCharacter(from: .decimalDigits), "no health values in notifications")
    }

    func testDenialKeepsReminderOffAndExplains() async {
        let scheduler = FakeScheduler(permission: .notDetermined, grant: false)
        let controller = ReminderController(scheduler: scheduler, defaults: defaults)
        await controller.setEnabled(.evening, true)
        XCTAssertFalse(controller.setting(.evening).enabled)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertEqual(controller.message, ReminderController.deniedMessage)

        // Later attempts with permission already denied do not ask again.
        await controller.setEnabled(.evening, true)
        XCTAssertEqual(scheduler.permissionRequests, 1)
        XCTAssertFalse(controller.setting(.evening).enabled)
    }

    func testTimeChangeReplacesPendingRequestAndDisableRemovesIt() async {
        let scheduler = FakeScheduler(permission: .allowed)
        let controller = ReminderController(scheduler: scheduler, defaults: defaults)
        await controller.setEnabled(.evening, true)
        await controller.setTime(.evening, hour: 21, minute: 30)
        XCTAssertEqual(scheduler.removed, [ReminderKind.evening.identifier])
        XCTAssertEqual(scheduler.scheduled[ReminderKind.evening.identifier]?.hour, 21)
        XCTAssertEqual(scheduler.scheduled[ReminderKind.evening.identifier]?.minute, 30)
        XCTAssertEqual(scheduler.scheduled.count, 1)

        await controller.setEnabled(.evening, false)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertFalse(controller.setting(.evening).enabled)
        XCTAssertEqual(controller.setting(.evening).hour, 21, "the chosen time is kept")
    }

    func testTimeChangeWhileOffSchedulesNothing() async {
        let scheduler = FakeScheduler(permission: .allowed)
        let controller = ReminderController(scheduler: scheduler, defaults: defaults)
        await controller.setTime(.morning, hour: 7, minute: 45)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        await controller.setEnabled(.morning, true)
        XCTAssertEqual(scheduler.scheduled[ReminderKind.morning.identifier]?.hour, 7)
    }

    func testSettingsPersistAcrossLaunches() async {
        let scheduler = FakeScheduler(permission: .allowed)
        let controller = ReminderController(scheduler: scheduler, defaults: defaults)
        await controller.setTime(.morning, hour: 6, minute: 30)
        await controller.setEnabled(.morning, true)
        let relaunched = ReminderController(scheduler: scheduler, defaults: defaults)
        XCTAssertEqual(relaunched.setting(.morning), ReminderSetting(enabled: true, hour: 6, minute: 30))
    }

    func testDisableAllRemovesEveryPendingReminder() async {
        let scheduler = FakeScheduler(permission: .allowed)
        let controller = ReminderController(scheduler: scheduler, defaults: defaults)
        await controller.setEnabled(.morning, true)
        await controller.setEnabled(.evening, true)
        controller.disableAll()
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertFalse(controller.setting(.morning).enabled)
        XCTAssertFalse(controller.setting(.evening).enabled)
    }

    func testReminderActivationOpensTheRightPlace() {
        let navigation = AppNavigation()
        navigation.selection = .trends
        navigation.handleReminder(ReminderKind(notificationIdentifier: ReminderKind.morning.identifier)!)
        XCTAssertEqual(navigation.selection, .today)
        XCTAssertEqual(navigation.sleepEntryRequest, 1)

        navigation.selection = .history
        navigation.handleReminder(.evening)
        XCTAssertEqual(navigation.selection, .today)
        XCTAssertEqual(navigation.windDownFocusRequest, 1)
        XCTAssertNil(ReminderKind(notificationIdentifier: "other"))
    }
}
