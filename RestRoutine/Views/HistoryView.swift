import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \SleepEntry.end, order: .reverse) private var sleep: [SleepEntry]
    @Query private var habitDays: [HabitDay]
    @AppStorage(PreferenceKey.waterUnit) private var waterUnitRaw = WaterUnit.milliliters.rawValue
    @Environment(\.theme) private var theme
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
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing + 6) {
                    ScreenHeader(title: "History", subtitle: "Recent dates, including unlogged days") {
                        HStack(spacing: 8) {
                            DatePicker("Open date", selection: $pickedDate, in: ...Date.now, displayedComponents: .date)
                                .labelsHidden()
                                .help("Choose any date to open")
                            Button("Open") { path = [DayKey(date: pickedDate)] }
                                .buttonStyle(.themed())
                                .help("Open the chosen date")
                        }
                    }

                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Date")
                            Spacer()
                            Text("Sleep · habits")
                        }
                        .font(theme.kicker)
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(theme.tint)

                        ForEach(dates) { day in
                            ThemeRule()
                            NavigationLink(value: day) {
                                HistoryRow(
                                    day: day,
                                    entry: sleep.first { $0.wakeDateKey == day.rawValue },
                                    habits: habitDays.first { $0.dateKey == day.rawValue },
                                    unit: unit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
                    .themePanel()
                }
                .padding(theme.screenPadding)
            }
            .background(theme.background)
            .navigationTitle("History")
            .hidesToolbarTitle()
            .navigationDestination(for: DayKey.self) { day in
                DateDetailView(day: day)
            }
        }
    }
}

struct HistoryRow: View {
    @Environment(\.theme) private var theme
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
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(day.mediumLabel)
                .font(theme.heading(15))
                .foregroundStyle(theme.ink)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(sleepText)
                    .font(theme.value.weight(.semibold))
                    .foregroundStyle(entry == nil ? theme.muted : theme.ink)
                Text(habitsText).font(.caption).foregroundStyle(theme.muted)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DateDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme
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
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing) {
                ScreenHeader(title: day.longLabel, subtitle: "Sleep and habits for this date")
                    .padding(.bottom, 6)

                ThemePanel(title: "Sleep (woke this date)") {
                    if let entry {
                        ThemeLine("In bed", Display.timeRange(entry))
                        ThemeLine("Time in bed", DurationText.format(entry.timeInBed))
                        ThemeLine("Estimated sleep", entry.estimatedSleep.map(DurationText.format) ?? "Unavailable",
                                  muted: entry.estimatedSleep == nil)
                        ThemeLine("Awake", entry.awakeMinutes.map { "\($0) min" } ?? "Not entered",
                                  muted: entry.awakeMinutes == nil)
                        ThemeLine("Quality", Display.quality(entry.quality), muted: entry.quality == nil)
                        ThemeLine("Source", entry.sourceLabel)
                        ThemeLine("Note", entry.note ?? "None", muted: entry.note == nil)
                        HStack {
                            Button("Edit sleep") { sleepSheet = .edit(entry.id) }
                                .buttonStyle(.themed())
                            Button("Delete sleep…", role: .destructive) { confirmDeleteSleep = true }
                                .buttonStyle(.themed(.destructive))
                        }
                        .padding(.top, 10)
                    } else {
                        ThemeLine("Sleep", "Not logged", muted: true)
                        Button("Log sleep for this date") { sleepSheet = .new(day) }
                            .buttonStyle(.themed())
                            .padding(.top, 10)
                    }
                }
                ThemePanel(title: "Habits") {
                    ThemeLine("Water", Display.water(habits?.waterMilliliters, unit: unit),
                              muted: habits?.waterMilliliters == nil)
                    ThemeLine("Movement", Display.movement(habits?.movementMinutes),
                              muted: habits?.movementMinutes == nil)
                    ThemeLine("Wind-down", Display.windDown(habits?.windDown), muted: habits?.windDown == nil)
                    ThemeLine("Note", habits?.note ?? "None", muted: habits?.note == nil)
                    HStack {
                        Button(habits == nil ? "Log habits" : "Edit habits") { editingHabits = true }
                            .buttonStyle(.themed())
                        if habits != nil {
                            Button("Delete habits…", role: .destructive) { confirmDeleteHabits = true }
                                .buttonStyle(.themed(.destructive))
                        }
                    }
                    .padding(.top, 10)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(theme.danger)
                }
            }
            .padding(theme.screenPadding)
        }
        .background(theme.background)
        .navigationTitle(day.longLabel)
        .hidesToolbarTitle()
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
