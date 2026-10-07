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
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: 120, y: 120), size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        // Rendered without ordering the window on screen, so nothing appears
        // on the desktop and window managers leave its size alone.
        windows.append(window)
        settle()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return window
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func capture(_ window: NSWindow, _ name: String) throws {
        settle(0.3)
        let view = window.contentView!.superview ?? window.contentView!
        let data: Data
        if let layer = view.layer {
            // Rendering the layer tree also draws the sidebar's labels, which
            // cacheDisplay leaves out.
            let scale = window.backingScaleFactor
            let width = Int(view.bounds.width * scale), height = Int(view.bounds.height * scale)
            let context = try XCTUnwrap(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            if view.isFlipped {
                context.translateBy(x: 0, y: view.bounds.height)
                context.scaleBy(x: 1, y: -1)
            }
            layer.render(in: context)
            let image = try XCTUnwrap(context.makeImage())
            data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        } else {
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        }
        let url = Self.outputDirectory.appendingPathComponent("\(name).png")
        try data.write(to: url)
        print("SNAPSHOT \(url.path)")
    }

    private func app(_ container: ModelContainer, _ destination: Destination,
                     navigation: AppNavigation? = nil) -> some View {
        let navigation = navigation ?? AppNavigation()
        navigation.selection = destination
        return ContentView(today: Self.today)
            .environmentObject(navigation)
            .environmentObject(ReminderController(scheduler: FakeScheduler(permission: .notDetermined),
                                                  defaults: UserDefaults(suiteName: "snap-\(UUID())")!))
            .modelContainer(container)
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
            SleepEntrySheet(request: .new(Self.today), initialDraft: draft).modelContainer(container)
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
        try capture(window(HabitEditorSheet(dateKey: Self.today).modelContainer(container), size: size, title: "Habits"),
                    "09-habit-editor-saved")
        let bad = HabitDraft(waterText: "-5", movementText: "12.5", windDown: .notDone)
        try capture(window(HabitEditorSheet(dateKey: Self.today, initialDraft: bad).modelContainer(container),
                           size: size, title: "Habits"), "10-habit-editor-invalid")
    }

    func testHistoryAndDetail() throws {
        let container = try monthContainer()
        try capture(window(app(container, .history), size: appSize), "11-history")
        let detail = DateDetailView(day: Self.today)
            .environmentObject(AppNavigation())
            .modelContainer(container)
        try capture(window(detail, size: CGSize(width: 620, height: 560), title: Self.today.longLabel),
                    "12-date-detail-logged")
        let gap = DateDetailView(day: Self.today.adding(days: -3)).modelContainer(container)
        try capture(window(gap, size: CGSize(width: 620, height: 440), title: "Unlogged date"),
                    "13-date-detail-unlogged")
    }

    func testTrends() throws {
        let container = try monthContainer()
        try capture(window(app(container, .trends), size: CGSize(width: 1040, height: 900)), "14-trends-7-days")
        let month = TrendsView(range: .month, today: Self.today).modelContainer(container)
        try capture(window(month, size: CGSize(width: 860, height: 900)), "15-trends-30-days")
        try capture(window(app(emptyContainer(), .trends), size: CGSize(width: 1040, height: 900)), "16-trends-empty")
    }

    func testSettingsStates() async throws {
        let container = try emptyContainer()
        func settings(_ controller: ReminderController) -> some View {
            SettingsView().environmentObject(controller).modelContainer(container)
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
    private func tables(in view: NSView) -> [NSTableView] {
        (view as? NSTableView).map { [$0] } ?? [] + view.subviews.flatMap { tables(in: $0) }
    }

    private func texts(in view: NSView) -> [String] {
        ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap { texts(in: $0) }
    }

    func testSidebarListsTodayHistoryAndTrends() throws {
        let navigation = AppNavigation()
        let container = try TestSupport.inMemoryStore().0
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 980, height: 620),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: ContentView(today: DayKey(rawValue: "2026-10-07")!)
            .environmentObject(navigation)
            .modelContainer(container))
        hosting.sizingOptions = []
        window.contentView = hosting
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView?.superview)
        let sidebar = try XCTUnwrap(tables(in: root).first, "sidebar list")
        XCTAssertEqual(sidebar.numberOfRows, 3)
        print("SIDEBAR rows=\(sidebar.numberOfRows) texts=\(texts(in: sidebar))")
    }
}
