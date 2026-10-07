import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import RestRoutine

@MainActor
final class ThemeTests: XCTestCase {
    func testStartsWithTheApprovedLook() {
        let theme = TestSupport.defaults().themeSettings
        XCTAssertEqual(theme, ThemeSettings(preset: .studio, appearance: .system, accent: .ocean, headings: .rounded))
        XCTAssertEqual(theme, .initial)
    }

    func testChoicesPersistAfterRelaunch() throws {
        let name = "ThemeTests-\(UUID().uuidString)"
        let chosen = ThemeSettings(preset: .signal, appearance: .dark, accent: .moss, headings: .serif)
        UserDefaults(suiteName: name)!.themeSettings = chosen
        // A new defaults object reads what a relaunched app would read.
        XCTAssertEqual(UserDefaults(suiteName: name)!.themeSettings, chosen)
        UserDefaults().removePersistentDomain(forName: name)
    }

    func testChoosingAPresetAppliesItsAccentAndHeadingsButKeepsAppearance() {
        var theme = ThemeSettings(preset: .studio, appearance: .dark, accent: .moss, headings: .system)
        theme.choose(.dusk)
        XCTAssertEqual(theme, ThemeSettings(preset: .dusk, appearance: .dark, accent: .ember, headings: .serif))
        theme.choose(.signal)
        XCTAssertEqual(theme, ThemeSettings(preset: .signal, appearance: .dark, accent: .iris, headings: .system))
        theme.choose(.studio)
        XCTAssertEqual(theme, ThemeSettings(preset: .studio, appearance: .dark, accent: .ocean, headings: .rounded))
    }

    func testUnknownSavedValuesFallBackSafely() {
        let defaults = TestSupport.defaults()
        defaults.set("neon", forKey: PreferenceKey.themePreset)
        defaults.set("sepia", forKey: PreferenceKey.themeAppearance)
        defaults.set("pink", forKey: PreferenceKey.themeAccent)
        defaults.set(42, forKey: PreferenceKey.themeHeadings)
        XCTAssertEqual(defaults.themeSettings, .initial)

        // A known preset with unknown details uses that preset's own accent and headings.
        defaults.set("dusk", forKey: PreferenceKey.themePreset)
        defaults.set("light", forKey: PreferenceKey.themeAppearance)
        XCTAssertEqual(defaults.themeSettings,
                       ThemeSettings(preset: .dusk, appearance: .light, accent: .ember, headings: .serif))
    }

    func testThemeStaysOutOfRecordBackups() throws {
        let (_, store) = try TestSupport.inMemoryStore()
        let defaults = TestSupport.defaults(ThemeSettings(preset: .signal, appearance: .dark, accent: .iris, headings: .serif))
        let reminders = Dictionary(uniqueKeysWithValues: ReminderKind.allCases.map { ($0, ReminderSetting.defaults(for: $0)) })
        let data = try BackupService.encode(BackupService.makeBackup(store: store, defaults: defaults, reminders: reminders))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        XCTAssertEqual(Set(preferences.keys), ["waterUnit", "morningReminder", "eveningReminder"])
        XCTAssertEqual(json["version"] as? Int, 1)
    }

    /// Text stays readable on every preset, accent and appearance.
    func testEveryCombinationKeepsTextReadable() {
        func luminance(_ color: Color) -> Double {
            let c = TestSupport.rgb(color)
            let linear = [c.red, c.green, c.blue].map { v -> Double in
                let x = Double(v) / 255
                return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        func contrast(_ a: Color, _ b: Color) -> Double {
            let (x, y) = (luminance(a), luminance(b))
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        for preset in ThemePreset.allCases {
            for accent in ThemeAccent.allCases {
                for dark in [false, true] {
                    let t = Theme(settings: ThemeSettings(preset: preset, appearance: .system, accent: accent,
                                                          headings: .system), isDark: dark)
                    let name = "\(preset) \(accent) \(dark ? "dark" : "light")"
                    XCTAssertGreaterThanOrEqual(contrast(t.ink, t.surface), 7, name)
                    XCTAssertGreaterThanOrEqual(contrast(t.muted, t.surface), 4.5, name)
                    XCTAssertGreaterThanOrEqual(contrast(t.muted, t.sidebar), 4.5, name)
                    XCTAssertGreaterThanOrEqual(contrast(t.onAccent, t.accent), 4.5, name)
                    XCTAssertGreaterThanOrEqual(contrast(t.accent, t.tint), 4.5, name)
                    XCTAssertGreaterThanOrEqual(contrast(t.danger, t.surface), 4.5, name)
                    // Increase Contrast draws borders as strongly as secondary text.
                    let strong = Theme(settings: t.settings, isDark: dark, highContrast: true)
                    XCTAssertGreaterThanOrEqual(contrast(strong.line, strong.surface), 4.5, name)
                }
            }
        }
    }
}

/// Drives the real Settings controls and checks every open window follows them.
@MainActor
final class ThemePropagationTests: XCTestCase {
    var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
    }

    private func open<V: View>(_ view: V, size: CGSize, dark: Bool = false) -> NSWindow {
        let window = TestSupport.window(view, size: size, dark: dark)
        windows.append(window)
        return window
    }

    private func reminders(_ defaults: UserDefaults) -> ReminderController {
        ReminderController(scheduler: FakeScheduler(permission: .allowed), defaults: defaults)
    }

    /// The main window, the Settings window and an editor, all reading one preferences store.
    private func openWindows(_ defaults: UserDefaults, container: ModelContainer, dark: Bool = false)
        -> (main: NSWindow, settings: NSWindow, editor: NSWindow) {
        let main = open(ContentView(today: SnapshotTests.today)
            .environmentObject(AppNavigation())
            .environmentObject(reminders(defaults))
            .modelContainer(container)
            .defaultAppStorage(defaults), size: CGSize(width: 980, height: 620), dark: dark)
        let settings = open(SettingsView()
            .environmentObject(reminders(defaults))
            .modelContainer(container)
            .defaultAppStorage(defaults), size: CGSize(width: 520, height: 680), dark: dark)
        let editor = open(HabitEditorSheet(dateKey: SnapshotTests.today)
            .themeRoot()
            .modelContainer(container)
            .defaultAppStorage(defaults), size: CGSize(width: 440, height: 400), dark: dark)
        return (main, settings, editor)
    }

    private func assertDrawn(_ windows: (main: NSWindow, settings: NSWindow, editor: NSWindow), with theme: Theme,
                             _ context: String, file: StaticString = #filePath, line: UInt = #line) throws {
        // Empty areas show each surface: the screen background, the Settings
        // background, and the editor's surface beside its buttons. Windows drawn
        // off screen leave out the sidebar, so the app's own pictures cover it.
        TestSupport.assertColor(try TestSupport.color(in: windows.main, at: CGPoint(x: 960, y: 600)), theme.background,
                                "\(context): main window background", file: file, line: line)
        TestSupport.assertColor(try TestSupport.color(in: windows.settings, at: CGPoint(x: 8, y: 340)), theme.background,
                                "\(context): Settings background", file: file, line: line)
        let editorBottom = windows.editor.contentView!.bounds.height - 16
        TestSupport.assertColor(try TestSupport.color(in: windows.editor, at: CGPoint(x: 60, y: editorBottom)), theme.surface,
                                "\(context): editor surface", file: file, line: line)
    }

    func testSettingsChangesRestyleEveryOpenWindow() throws {
        let defaults = TestSupport.defaults()
        let container = try TestSupport.inMemoryStore().0
        let opened = openWindows(defaults, container: container)
        try assertDrawn(opened, with: Theme(settings: .initial, isDark: false), "starting look")

        TestSupport.choose("Quiet signal", from: "Preset", in: opened.settings)
        let signal = ThemeSettings(preset: .signal, appearance: .system, accent: .iris, headings: .system)
        XCTAssertEqual(defaults.themeSettings, signal, "a preset sets its accent and headings and keeps appearance")
        try assertDrawn(opened, with: Theme(settings: signal, isDark: false), "after choosing Quiet signal")

        TestSupport.choose("Dark", from: "Appearance", in: opened.settings)
        XCTAssertEqual(defaults.themeSettings.appearance, .dark)
        try assertDrawn(opened, with: Theme(settings: defaults.themeSettings, isDark: true), "after choosing Dark")

        TestSupport.choose("Moss", from: "Accent", in: opened.settings)
        XCTAssertEqual(defaults.themeSettings.accent, .moss)
        XCTAssertEqual(defaults.themeSettings.preset, .signal, "an accent leaves the preset alone")
        TestSupport.choose("Journal · serif", from: "Headings", in: opened.settings)
        XCTAssertEqual(defaults.themeSettings.headings, .serif)
        TestSupport.choose("Light", from: "Appearance", in: opened.settings)
        try assertDrawn(opened, with: Theme(settings: defaults.themeSettings, isDark: false), "after choosing Light")
    }

    func testEditorSheetsFollowTheTheme() throws {
        let theme = ThemeSettings(preset: .dusk, appearance: .dark, accent: .ember, headings: .serif)
        let defaults = TestSupport.defaults(theme)
        let navigation = AppNavigation()
        let main = open(ContentView(today: SnapshotTests.today)
            .environmentObject(navigation)
            .environmentObject(reminders(defaults))
            .modelContainer(try TestSupport.inMemoryStore().0)
            .defaultAppStorage(defaults), size: CGSize(width: 980, height: 620))
        // Sheets open only on a visible window, so this one sits beyond the
        // edge of every display, where nobody sees it.
        main.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        main.orderFrontRegardless()
        navigation.sleepEntryRequest += 1
        TestSupport.settle()
        let sheet = try XCTUnwrap(main.attachedSheet, "Log sleep opens a sheet")
        defer { main.endSheet(sheet) }
        let bottom = sheet.contentView!.bounds.height - 16
        TestSupport.assertColor(try TestSupport.color(in: sheet, at: CGPoint(x: 60, y: bottom)),
                                Theme(settings: theme, isDark: true).surface, "sleep sheet surface")
    }

    func testFollowSystemUsesTheMacAppearance() throws {
        let defaults = TestSupport.defaults(ThemeSettings(preset: .dusk, appearance: .system, accent: .ember, headings: .serif))
        let container = try TestSupport.inMemoryStore().0
        let opened = openWindows(defaults, container: container, dark: true)
        try assertDrawn(opened, with: Theme(settings: defaults.themeSettings, isDark: true), "dark Mac")
    }

    func testResetAppearanceRestoresTheStartingLookOnly() async throws {
        let theme = ThemeSettings(preset: .dusk, appearance: .dark, accent: .moss, headings: .system)
        let defaults = TestSupport.defaults(theme)
        defaults.waterUnit = .usFluidOunces
        let controller = reminders(defaults)
        await controller.setTime(.evening, hour: 21, minute: 30)
        await controller.setEnabled(.evening, true)
        let (container, store) = try TestSupport.inMemoryStore()
        try store.saveSleep(SleepDraft(
            start: TestSupport.date(2026, 10, 6, 23), end: TestSupport.date(2026, 10, 7, 7),
            timeZoneIdentifier: "America/Chicago", awakeMinutesText: "30", quality: 3))
        try store.saveHabits(HabitDraft(waterText: "12", movementText: "0", windDown: .notDone),
                             dateKey: "2026-10-07", unit: .usFluidOunces)
        let opened = openWindows(defaults, container: container)
        try assertDrawn(opened, with: Theme(settings: theme, isDark: true), "chosen look")

        TestSupport.press("Reset appearance", in: opened.settings)

        XCTAssertEqual(defaults.themeSettings, .initial)
        XCTAssertEqual(defaults.waterUnit, .usFluidOunces, "units are untouched")
        XCTAssertEqual(reminders(defaults).setting(.evening), ReminderSetting(enabled: true, hour: 21, minute: 30),
                       "reminders are untouched")
        XCTAssertEqual(try store.allSleep().count, 1, "records are untouched")
        XCTAssertEqual(try store.habitDay(dateKey: "2026-10-07")?.movementMinutes, 0)
        XCTAssertEqual(try store.habitDay(dateKey: "2026-10-07")?.windDown, .notDone)
        try assertDrawn(opened, with: Theme(settings: .initial, isDark: false), "after reset")
    }
}
