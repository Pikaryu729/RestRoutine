import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import RestRoutine

/// Renders the app's real views in windows with disposable sample records and
/// saves pictures under the app container's temporary folder for review.
@MainActor
final class SnapshotTests: XCTestCase {
    static let today = DayKey(rawValue: "2026-10-07")!
    static var outputDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("RestRoutineSnapshots", isDirectory: true)
    }

    var windows: [NSWindow] = []

    override func setUp() async throws {
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        UserDefaults.standard.waterUnit = .milliliters
    }

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
    }

    // MARK: Sample data

    private func emptyContainer() throws -> ModelContainer {
        try TestSupport.inMemoryStore().0
    }

    /// One saved night and today's habits, matching the plan's example.
    private func savedContainer() throws -> ModelContainer {
        let (container, store) = try TestSupport.inMemoryStore()
        try store.saveSleep(SleepDraft(
            start: TestSupport.date(2026, 10, 6, 23), end: TestSupport.date(2026, 10, 7, 7),
            timeZoneIdentifier: "America/Chicago", awakeMinutesText: "30", quality: 3))
        try store.saveHabits(HabitDraft(waterText: "1000", movementText: "20"), dateKey: "2026-10-07", unit: .milliliters)
        return container
    }

    /// Thirty days with deliberate gaps.
    private func monthContainer() throws -> ModelContainer {
        let (container, store) = try TestSupport.inMemoryStore()
        for offset in 0..<30 {
            let day = Self.today.adding(days: -offset)
            let c = day.components
            if offset % 5 != 3 {
                let bedHour = 22 + offset % 2
                let start = TestSupport.date(c.year!, c.month!, c.day!, bedHour, (offset * 7) % 60)
                    .addingTimeInterval(-24 * 3600)
                let end = TestSupport.date(c.year!, c.month!, c.day!, 6 + offset % 2, (offset * 11) % 60)
                try store.saveSleep(SleepDraft(
                    start: start, end: end, timeZoneIdentifier: "America/Chicago",
                    awakeMinutesText: offset % 4 == 1 ? "" : "\(15 + (offset * 5) % 40)",
                    quality: offset % 3 == 2 ? nil : 2 + offset % 4))
            }
            if offset % 6 != 4 {
                try store.saveHabits(HabitDraft(
                    waterText: offset % 7 == 5 ? "0" : "\(750 + (offset * 130) % 1200)",
                    movementText: offset % 3 == 0 ? "" : "\((offset * 9) % 60)",
                    windDown: offset % 4 == 0 ? .notDone : (offset % 4 == 2 ? nil : .done)),
                    dateKey: day.rawValue, unit: .milliliters)
            }
        }
        return container
    }

    // MARK: Rendering

    @discardableResult
    private func window<V: View>(_ view: V, size: CGSize, title: String = "Rest & Routine",
                                 dark: Bool = false) -> NSWindow {
        let window = TestSupport.window(view, size: size, title: title, dark: dark)
        windows.append(window)
        return window
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        TestSupport.settle(seconds)
    }

    private func capture(_ window: NSWindow, _ name: String) throws {
        let image = try TestSupport.image(of: window)
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let url = Self.outputDirectory.appendingPathComponent("\(name).png")
        try data.write(to: url)
        print("SNAPSHOT \(url.path)")
    }

    private func app(_ container: ModelContainer, _ destination: Destination,
                     navigation: AppNavigation? = nil, theme: ThemeSettings? = nil) -> some View {
        let navigation = navigation ?? AppNavigation()
        navigation.selection = destination
        return ContentView(today: Self.today)
            .environmentObject(navigation)
            .environmentObject(ReminderController(scheduler: FakeScheduler(permission: .notDetermined),
                                                  defaults: UserDefaults(suiteName: "snap-\(UUID())")!))
            .modelContainer(container)
            .defaultAppStorage(TestSupport.defaults(theme))
    }

    private let appSize = CGSize(width: 980, height: 620)

    // MARK: Pictures

    func testTodayEmptyAndSaved() throws {
        try capture(window(app(emptyContainer(), .today), size: appSize), "01-today-empty")
        try capture(window(app(savedContainer(), .today), size: appSize), "02-today-saved")
        try capture(window(app(savedContainer(), .today), size: appSize, dark: true), "03-today-saved-dark")
    }

    func testEveningReminderFocusesWindDown() throws {
        let navigation = AppNavigation()
        let w = try window(app(savedContainer(), .trends, navigation: navigation), size: appSize)
        navigation.handleReminder(.evening)
        settle()
        try capture(w, "04-today-after-evening-reminder")
    }

    func testSleepSheetStates() throws {
        let container = try emptyContainer()
        func sheet(_ draft: SleepDraft?) -> some View {
            SleepEntrySheet(request: .new(Self.today), initialDraft: draft).themeRoot().modelContainer(container)
                .defaultAppStorage(TestSupport.defaults())
        }
        let base = SleepDraft.defaultFor(wakeDate: Self.today, calendar: TestSupport.calendar())
        var withAwake = base
        withAwake.awakeMinutesText = "30"
        withAwake.quality = 3
        var invalid = base
        invalid.awakeMinutesText = "600"
        var backwards = base
        backwards.end = base.start
        let size = CGSize(width: 460, height: 420)
        try capture(window(sheet(nil), size: size, title: "Log sleep"), "05-sleep-sheet-blank-awake")
        try capture(window(sheet(withAwake), size: size, title: "Log sleep"), "06-sleep-sheet-with-awake")
        try capture(window(sheet(invalid), size: size, title: "Log sleep"), "07-sleep-sheet-invalid-awake")
        try capture(window(sheet(backwards), size: size, title: "Log sleep"), "08-sleep-sheet-end-before-start")
    }

    func testHabitEditorStates() throws {
        let container = try savedContainer()
        let size = CGSize(width: 440, height: 400)
        try capture(window(HabitEditorSheet(dateKey: Self.today).themeRoot().modelContainer(container)
                            .defaultAppStorage(TestSupport.defaults()), size: size, title: "Habits"),
                    "09-habit-editor-saved")
        let bad = HabitDraft(waterText: "-5", movementText: "12.5", windDown: .notDone)
        try capture(window(HabitEditorSheet(dateKey: Self.today, initialDraft: bad).themeRoot().modelContainer(container)
                            .defaultAppStorage(TestSupport.defaults()), size: size, title: "Habits"),
                    "10-habit-editor-invalid")
    }

    func testHistoryAndDetail() throws {
        let container = try monthContainer()
        try capture(window(app(container, .history), size: appSize), "11-history")
        let detail = DateDetailView(day: Self.today)
            .themeRoot()
            .environmentObject(AppNavigation())
            .modelContainer(container)
            .defaultAppStorage(TestSupport.defaults())
        try capture(window(detail, size: CGSize(width: 620, height: 560), title: Self.today.longLabel),
                    "12-date-detail-logged")
        let gap = DateDetailView(day: Self.today.adding(days: -3)).themeRoot().modelContainer(container)
            .defaultAppStorage(TestSupport.defaults())
        try capture(window(gap, size: CGSize(width: 620, height: 440), title: "Unlogged date"),
                    "13-date-detail-unlogged")
    }

    func testTrends() throws {
        let container = try monthContainer()
        try capture(window(app(container, .trends), size: CGSize(width: 1040, height: 900)), "14-trends-7-days")
        let month = TrendsView(range: .month, today: Self.today).themeRoot().modelContainer(container)
            .defaultAppStorage(TestSupport.defaults())
        try capture(window(month, size: CGSize(width: 860, height: 900)), "15-trends-30-days")
        try capture(window(app(emptyContainer(), .trends), size: CGSize(width: 1040, height: 900)), "16-trends-empty")
    }

    /// One night without awake minutes, and habits logged as zero and Not done.
    private func edgeContainer() throws -> ModelContainer {
        let (container, store) = try TestSupport.inMemoryStore()
        try store.saveSleep(SleepDraft(
            start: TestSupport.date(2026, 10, 6, 23), end: TestSupport.date(2026, 10, 7, 7),
            timeZoneIdentifier: "America/Chicago", awakeMinutesText: "", quality: nil))
        try store.saveHabits(HabitDraft(waterText: "0", movementText: "0", windDown: .notDone),
                             dateKey: "2026-10-07", unit: .milliliters)
        return container
    }

    func testRecordStatesKeepTheirMeaning() throws {
        try capture(window(app(edgeContainer(), .today), size: appSize), "20-today-missing-estimate-zero-not-done")
        try capture(window(app(edgeContainer(), .today), size: CGSize(width: 820, height: 520)),
                    "21-today-minimum-window")
    }

    func testEveryPresetInLightAndDark() throws {
        let saved = try savedContainer()
        let month = try monthContainer()
        let reminders = ReminderController(scheduler: FakeScheduler(permission: .notDetermined),
                                           defaults: UserDefaults(suiteName: "snap-\(UUID())")!)
        for preset in ThemePreset.allCases {
            var theme = ThemeSettings.initial
            theme.choose(preset)
            for dark in [false, true] {
                let suffix = "\(preset.rawValue)-\(dark ? "dark" : "light")"
                try capture(window(app(saved, .today, theme: theme), size: appSize, dark: dark), "30-today-\(suffix)")
                try capture(window(app(month, .history, theme: theme), size: appSize, dark: dark), "31-history-\(suffix)")
                try capture(window(app(month, .trends, theme: theme), size: CGSize(width: 1040, height: 900), dark: dark),
                            "32-trends-\(suffix)")
                try capture(window(SettingsView().environmentObject(reminders).modelContainer(saved)
                                    .defaultAppStorage(TestSupport.defaults(theme)),
                                   size: CGSize(width: 520, height: 680), title: "Settings", dark: dark),
                            "33-settings-\(suffix)")
                try capture(window(SleepEntrySheet(request: .new(Self.today)).themeRoot().modelContainer(saved)
                                    .defaultAppStorage(TestSupport.defaults(theme)),
                                   size: CGSize(width: 460, height: 420), title: "Log sleep", dark: dark),
                            "34-sleep-sheet-\(suffix)")
            }
        }
    }

    func testAccentsAndHeadingsAreIndependent() throws {
        let saved = try savedContainer()
        for accent in ThemeAccent.allCases {
            let theme = ThemeSettings(preset: .dusk, appearance: .system, accent: accent, headings: .rounded)
            try capture(window(app(saved, .today, theme: theme), size: appSize), "35-today-dusk-\(accent.rawValue)-rounded")
        }
    }

    func testSettingsStates() async throws {
        let container = try emptyContainer()
        func settings(_ controller: ReminderController) -> some View {
            SettingsView().environmentObject(controller).modelContainer(container)
                .defaultAppStorage(TestSupport.defaults())
        }
        let size = CGSize(width: 520, height: 680)
        let off = ReminderController(scheduler: FakeScheduler(permission: .notDetermined),
                                     defaults: UserDefaults(suiteName: "snap-\(UUID())")!)
        try capture(window(settings(off), size: size, title: "Settings"), "17-settings-default")

        let denied = ReminderController(scheduler: FakeScheduler(permission: .notDetermined, grant: false),
                                        defaults: UserDefaults(suiteName: "snap-\(UUID())")!)
        await denied.setEnabled(.morning, true)
        try capture(window(settings(denied), size: size, title: "Settings"), "18-settings-permission-denied")

        let allowed = ReminderController(scheduler: FakeScheduler(permission: .allowed),
                                         defaults: UserDefaults(suiteName: "snap-\(UUID())")!)
        await allowed.setTime(.evening, hour: 21, minute: 30)
        await allowed.setEnabled(.evening, true)
        try capture(window(settings(allowed), size: size, title: "Settings"), "19-settings-evening-on")
    }
}

@MainActor
final class SidebarTests: XCTestCase {
    func testSidebarOpensTodayHistoryAndTrends() throws {
        let navigation = AppNavigation()
        let container = try TestSupport.inMemoryStore().0
        let window = TestSupport.window(
            ContentView(today: DayKey(rawValue: "2026-10-07")!)
                .environmentObject(navigation)
                .modelContainer(container)
                .defaultAppStorage(TestSupport.defaults()),
            size: CGSize(width: 980, height: 620))
        defer { window.close() }
        let labels = TestSupport.buttonLabels(in: window)
        for name in ["Today", "History", "Trends", "Settings"] {
            XCTAssertTrue(labels.contains(name), "sidebar offers \(name); buttons: \(labels)")
        }

        TestSupport.press("History", in: window)
        XCTAssertEqual(navigation.selection, .history)
        TestSupport.press("Trends", in: window)
        XCTAssertEqual(navigation.selection, .trends)
        TestSupport.press("Today", in: window)
        XCTAssertEqual(navigation.selection, .today)
    }
}
