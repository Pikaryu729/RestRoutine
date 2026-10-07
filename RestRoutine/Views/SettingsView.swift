import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        SettingsForm().themeRoot()
    }
}

private struct SettingsForm: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var reminders: ReminderController
    @Environment(\.theme) private var theme
    @AppStorage(PreferenceKey.waterUnit) private var waterUnitRaw = WaterUnit.milliliters.rawValue

    @State private var showBackupWarning = false
    @State private var exportDocument: BackupDocument?
    @State private var showImporter = false
    @State private var pendingRestore: BackupFile?
    @State private var confirmDeleteAll = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var store: JournalStore { JournalStore(context: context) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AppearanceSection()

                ThemePanel(title: "Units") {
                    SettingRow("Water") {
                        Picker("Water", selection: $waterUnitRaw) {
                            ForEach(WaterUnit.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    }
                }

                ThemePanel(title: "Reminders") {
                    ForEach(ReminderKind.allCases) { kind in
                        ReminderRow(kind: kind)
                    }
                    if let message = reminders.message {
                        Label(message, systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                            .font(.callout)
                            .padding(.top, 6)
                    }
                    SettingFooter("Both reminders start off. Turning one on asks for permission to show notifications. Reminders show no health values, and macOS may not deliver them while your Mac is asleep, powered off or in a Focus.")
                }

                ThemePanel(title: "Backup and restore") {
                    HStack {
                        Button("Back Up Records…") { showBackupWarning = true }
                            .buttonStyle(.themed())
                        Button("Restore from Backup…") { showImporter = true }
                            .buttonStyle(.themed())
                    }
                    SettingFooter("Your records stay on this Mac. A backup is a file you choose where to save; it is not encrypted. Restoring replaces all current records after you confirm.")
                }

                ThemePanel(title: "Privacy") {
                    Button("Delete All Records…", role: .destructive) { confirmDeleteAll = true }
                        .buttonStyle(.themed(.destructive))
                    SettingFooter("Records are stored only in this app's private folder on your Mac, without separate encryption. Deleting removes them and turns off reminders; it does not touch backup files you saved elsewhere.")
                }

                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle").foregroundStyle(.green)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(theme.danger)
                }
            }
            .padding(20)
        }
        .frame(minHeight: 420, idealHeight: 680)
        .background(theme.background)
        .navigationTitle("Settings")
        .alert("Back up your records?", isPresented: $showBackupWarning) {
            Button("Choose Location…") { prepareBackup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The backup file contains your sleep and habit records without encryption. Anyone or any software that can open the file can read it.")
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument, contentType: .json, defaultFilename: BackupService.suggestedFileName()
        ) { result in
            switch result {
            case .success: statusMessage = "Backup saved."
            case .failure: errorMessage = "The backup could not be saved."
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            readBackup(result)
        }
        .confirmationDialog(
            "Replace all current records with this backup?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { file in
            Button("Replace All Records", role: .destructive) { restore(file) }
        } message: { file in
            Text("The backup from \(file.exportedAt.formatted(date: .abbreviated, time: .shortened)) has \(file.sleepEntries.count) sleep entries and \(file.habitDays.count) habit days. Your current records will be replaced. This cannot be undone.")
        }
        .confirmationDialog("Delete all records?", isPresented: $confirmDeleteAll) {
            Button("Delete All Records", role: .destructive) { deleteAll() }
        } message: {
            Text("Every sleep entry and habit record in Rest & Routine will be removed, and reminders turned off. Backup files you saved are not affected. This cannot be undone.")
        }
    }

    private func clearMessages() {
        statusMessage = nil
        errorMessage = nil
    }

    private func prepareBackup() {
        clearMessages()
        do {
            let file = try BackupService.makeBackup(store: store, defaults: .standard, reminders: reminders.settings)
            exportDocument = BackupDocument(data: try BackupService.encode(file))
        } catch {
            errorMessage = "The backup could not be created."
        }
    }

    private func readBackup(_ result: Result<URL, Error>) {
        clearMessages()
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pendingRestore = try BackupService.validate(data)
        } catch let error as BackupError {
            errorMessage = "\(error.localizedDescription) Your current records were not changed."
        } catch {
            errorMessage = "The file could not be read. Your current records were not changed."
        }
    }

    private func restore(_ file: BackupFile) {
        clearMessages()
        do {
            try BackupService.restore(file, into: context)
            waterUnitRaw = file.preferences.waterUnit
            reminders.applyRestored([.morning: file.preferences.morningReminder, .evening: file.preferences.eveningReminder])
            statusMessage = "Records restored. Reminder times were restored; turn reminders on again if you want them."
        } catch {
            errorMessage = "The restore failed. Your current records were not changed."
        }
    }

    private func deleteAll() {
        clearMessages()
        do {
            try store.deleteAll()
            reminders.disableAll()
            statusMessage = "All records deleted."
        } catch {
            errorMessage = "The records could not be deleted."
        }
    }
}

/// Preset, appearance, accent and headings. Changes apply at once to every
/// window and are kept on this Mac only, outside record backups.
struct AppearanceSection: View {
    @Environment(\.theme) private var theme
    @AppStorage(PreferenceKey.themePreset) private var preset: String?
    @AppStorage(PreferenceKey.themeAppearance) private var appearance: String?
    @AppStorage(PreferenceKey.themeAccent) private var accent: String?
    @AppStorage(PreferenceKey.themeHeadings) private var headings: String?

    private var settings: ThemeSettings {
        ThemeSettings(preset: preset, appearance: appearance, accent: accent, headings: headings)
    }

    private func save(_ new: ThemeSettings) {
        preset = new.preset.rawValue
        appearance = new.appearance.rawValue
        accent = new.accent.rawValue
        headings = new.headings.rawValue
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ThemeSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { var s = settings; s[keyPath: keyPath] = $0; save(s) })
    }

    var body: some View {
        ThemePanel(title: "Appearance") {
            SettingRow("Preset") {
                Picker("Preset", selection: Binding(get: { settings.preset },
                                                    set: { var s = settings; s.choose($0); save(s) })) {
                    ForEach(ThemePreset.allCases) { Text($0.title).tag($0) }
                }
            }
            SettingRow("Appearance") {
                Picker("Appearance", selection: binding(\.appearance)) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
            }
            SettingRow("Accent") {
                Picker("Accent", selection: binding(\.accent)) {
                    ForEach(ThemeAccent.allCases) { Text($0.title).tag($0) }
                }
            }
            SettingRow("Headings") {
                Picker("Headings", selection: binding(\.headings)) {
                    ForEach(HeadingStyle.allCases) { Text($0.title).tag($0) }
                }
            }
            HStack {
                Text("Changes apply immediately.").foregroundStyle(theme.muted)
                Spacer()
                Button("Reset appearance") { save(.initial) }
                    .buttonStyle(.themed())
                    .help("Return to Soft studio, Follow system, Ocean and rounded headings")
            }
            .padding(.top, 8)
            SettingFooter("Choosing a preset also sets its accent and headings. Appearance stays as you chose it. Reset changes only the appearance, never your units, reminders or records.")
        }
    }
}

struct SettingRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer(minLength: 16)
            control
                .labelsHidden()
                .fixedSize()
        }
        .padding(.vertical, 3)
    }
}

struct SettingFooter: View {
    @Environment(\.theme) private var theme
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }
}

struct ReminderRow: View {
    @EnvironmentObject private var reminders: ReminderController
    let kind: ReminderKind

    private var setting: ReminderSetting { reminders.setting(kind) }

    private var time: Binding<Date> {
        Binding(
            get: { DayKey.today().date(hour: setting.hour, minute: setting.minute) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                Task { await reminders.setTime(kind, hour: c.hour ?? 0, minute: c.minute ?? 0) }
            })
    }

    private var enabled: Binding<Bool> {
        Binding(get: { setting.enabled }, set: { on in Task { await reminders.setEnabled(kind, on) } })
    }

    var body: some View {
        HStack {
            Toggle(kind.title, isOn: enabled)
            Spacer()
            DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .accessibilityLabel("\(kind.title) time")
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
