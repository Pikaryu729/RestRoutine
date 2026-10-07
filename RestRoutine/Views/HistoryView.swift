import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \SleepEntry.end, order: .reverse) private var sleep: [SleepEntry]
    @Query private var habitDays: [HabitDay]
    @AppStorage(PreferenceKey.waterUnit) private var waterUnitRaw = WaterUnit.milliliters.rawValue
    @State private var path: [DayKey] = []
    @State private var pickedDate = Date.now

    var today: DayKey = .today()

    private var unit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .milliliters }

    /// The last 30 dates, plus any older logged dates, newest first.
    private var dates: [DayKey] {
        var keys = Set(today.trailing(30))
        for entry in sleep { if let k = DayKey(rawValue: entry.wakeDateKey) { keys.insert(k) } }
        for day in habitDays { if let k = DayKey(rawValue: day.dateKey) { keys.insert(k) } }
        return keys.filter { $0 <= today }.sorted(by: >)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(dates) { day in
                        NavigationLink(value: day) {
                            HistoryRow(
                                day: day,
                                entry: sleep.first { $0.wakeDateKey == day.rawValue },
                                habits: habitDays.first { $0.dateKey == day.rawValue },
                                unit: unit)
                        }
                    }
                } header: {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text("Sleep · habits")
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: DayKey.self) { day in
                DateDetailView(day: day)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    DatePicker("Open date", selection: $pickedDate, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                        .help("Choose any date to open")
                    Button("Open") { path = [DayKey(date: pickedDate)] }
                        .help("Open the chosen date")
                }
            }
        }
    }
}

struct HistoryRow: View {
    let day: DayKey
    let entry: SleepEntry?
    let habits: HabitDay?
    let unit: WaterUnit

    private var sleepText: String {
        guard let entry else { return "Sleep not logged" }
        if let estimate = entry.estimatedSleep { return "\(DurationText.format(estimate)) estimated sleep" }
        return "\(DurationText.format(entry.timeInBed)) in bed"
    }

    private var habitsText: String {
        guard let habits, !habits.isEmpty else { return "Habits not logged" }
        return [
            "Water \(Display.water(habits.waterMilliliters, unit: unit))",
            "Movement \(Display.movement(habits.movementMinutes))",
            "Wind-down \(Display.windDown(habits.windDown))",
        ].joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(day.mediumLabel).frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(sleepText).foregroundStyle(entry == nil ? .secondary : .primary)
                Text(habitsText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct DateDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var sleep: [SleepEntry]
    @Query private var habitDays: [HabitDay]
    @AppStorage(PreferenceKey.waterUnit) private var waterUnitRaw = WaterUnit.milliliters.rawValue
    @State private var sleepSheet: SleepSheetRequest?
    @State private var editingHabits = false
    @State private var confirmDeleteSleep = false
    @State private var confirmDeleteHabits = false
    @State private var errorMessage: String?

    let day: DayKey

    init(day: DayKey) {
        self.day = day
        let key = day.rawValue
        _sleep = Query(filter: #Predicate<SleepEntry> { $0.wakeDateKey == key })
        _habitDays = Query(filter: #Predicate<HabitDay> { $0.dateKey == key })
    }

    private var unit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .milliliters }
    private var entry: SleepEntry? { sleep.first }
    private var habits: HabitDay? { habitDays.first }
    private var store: JournalStore { JournalStore(context: context) }

    var body: some View {
        Form {
            Section("Sleep (woke this date)") {
                if let entry {
                    LabeledContent("In bed", value: Display.timeRange(entry))
                    LabeledContent("Time in bed", value: DurationText.format(entry.timeInBed))
                    LabeledContent("Estimated sleep", value: entry.estimatedSleep.map(DurationText.format) ?? "Unavailable")
                    LabeledContent("Awake", value: entry.awakeMinutes.map { "\($0) min" } ?? "Not entered")
                    LabeledContent("Quality", value: Display.quality(entry.quality))
                    LabeledContent("Source", value: entry.sourceLabel)
                    LabeledContent("Note", value: entry.note ?? "None")
                    HStack {
                        Button("Edit sleep") { sleepSheet = .edit(entry.id) }
                        Button("Delete sleep…", role: .destructive) { confirmDeleteSleep = true }
                    }
                } else {
                    LabeledContent("Sleep", value: "Not logged")
                    Button("Log sleep for this date") { sleepSheet = .new(day) }
                }
            }
            Section("Habits") {
                LabeledContent("Water", value: Display.water(habits?.waterMilliliters, unit: unit))
                LabeledContent("Movement", value: Display.movement(habits?.movementMinutes))
                LabeledContent("Wind-down", value: Display.windDown(habits?.windDown))
                LabeledContent("Note", value: habits?.note ?? "None")
                HStack {
                    Button(habits == nil ? "Log habits" : "Edit habits") { editingHabits = true }
                    if habits != nil {
                        Button("Delete habits…", role: .destructive) { confirmDeleteHabits = true }
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(day.longLabel)
        .sheet(item: $sleepSheet) { SleepEntrySheet(request: $0) }
        .sheet(isPresented: $editingHabits) { HabitEditorSheet(dateKey: day) }
        .confirmationDialog("Delete the sleep entry for \(day.longLabel)?", isPresented: $confirmDeleteSleep) {
            Button("Delete sleep entry", role: .destructive) {
                guard let entry else { return }
                do { try store.deleteSleep(entry) } catch { errorMessage = "The entry could not be deleted." }
            }
        } message: {
            Text("This cannot be undone.")
        }
        .confirmationDialog("Delete the habits for \(day.longLabel)?", isPresented: $confirmDeleteHabits) {
            Button("Delete habits", role: .destructive) {
                do { try store.deleteHabits(dateKey: day.rawValue) } catch { errorMessage = "The habits could not be deleted." }
            }
        } message: {
            Text("Water, movement, wind-down and the note for this date return to Not logged. This cannot be undone.")
        }
    }
}
