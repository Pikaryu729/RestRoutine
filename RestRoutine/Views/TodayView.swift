import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var navigation: AppNavigation
    @Query(sort: \SleepEntry.end, order: .reverse) private var sleep: [SleepEntry]
    @Query private var habitDays: [HabitDay]
    @AppStorage(PreferenceKey.waterUnit) private var waterUnitRaw = WaterUnit.milliliters.rawValue
    @State private var sleepSheet: SleepSheetRequest?
    @State private var habitEditor: HabitField?
    @FocusState private var focusedHabit: HabitField?

    /// Overrides the current date, for previews and tests.
    var today: DayKey = .today()

    private var unit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .milliliters }
    private var todayHabits: HabitDay? { habitDays.first { $0.dateKey == today.rawValue } }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                SleepSummaryCard(entry: sleep.first) { entry in
                    sleepSheet = .edit(entry.id)
                } onLog: {
                    sleepSheet = .new(today)
                }
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)

                HabitsCard(
                    day: todayHabits, unit: unit, focusedHabit: $focusedHabit,
                    onSelect: { habitEditor = $0 })
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(20)
        }
        .navigationTitle("Today · \(today.shortLabel)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sleepSheet = .new(today)
                } label: {
                    Label("Log sleep", systemImage: "bed.double")
                        .labelStyle(.titleAndIcon)
                }
                .help("Log sleep (⌘L)")
            }
        }
        .sheet(item: $sleepSheet) { request in
            SleepEntrySheet(request: request)
        }
        .sheet(item: $habitEditor) { field in
            HabitEditorSheet(dateKey: today, initialFocus: field)
        }
        .onChange(of: navigation.sleepEntryRequest) { _, _ in sleepSheet = .new(today) }
        .onChange(of: navigation.windDownFocusRequest) { _, _ in focusedHabit = .windDown }
        .onAppear {
            if navigation.windDownFocusRequest > 0 { focusedHabit = .windDown }
        }
    }
}

struct SleepSummaryCard: View {
    let entry: SleepEntry?
    let onEdit: (SleepEntry) -> Void
    let onLog: () -> Void

    var body: some View {
        GroupBox {
            if let entry {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Woke \(DayKey(rawValue: entry.wakeDateKey)?.mediumLabel ?? entry.wakeDateKey)")
                        .font(.headline)
                    Text(Display.timeRange(entry))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Divider()
                    SummaryRow("Time in bed", DurationText.format(entry.timeInBed))
                    SummaryRow("Estimated sleep", entry.estimatedSleep.map(DurationText.format) ?? "Unavailable",
                               muted: entry.estimatedSleep == nil)
                    if entry.estimatedSleep == nil {
                        Text("Add awake minutes to estimate sleep. Time in bed is not the same as sleep.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    SummaryRow("Awake", entry.awakeMinutes.map { "\($0) min" } ?? "Not entered",
                               muted: entry.awakeMinutes == nil)
                    SummaryRow("Quality", Display.quality(entry.quality), muted: entry.quality == nil)
                    SummaryRow("Source", entry.sourceLabel)
                    if let note = entry.note {
                        Text(note).font(.callout).foregroundStyle(.secondary)
                    }
                    Button("Edit") { onEdit(entry) }
                }
                .padding(6)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No sleep logged yet").font(.headline)
                    Text("Log when you went to bed and when you woke up.")
                        .foregroundStyle(.secondary)
                    Button("Log sleep", action: onLog)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label("Last sleep", systemImage: "moon.zzz")
        }
        .accessibilityElement(children: .contain)
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    var muted = false

    init(_ label: String, _ value: String, muted: Bool = false) {
        self.label = label
        self.value = value
        self.muted = muted
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(muted ? .secondary : .primary)
        }
        .accessibilityElement(children: .combine)
    }
}

enum HabitField: String, Identifiable, Hashable, CaseIterable {
    case water, movement, windDown
    var id: String { rawValue }

    var title: String {
        switch self {
        case .water: "Water"
        case .movement: "Movement"
        case .windDown: "Wind-down"
        }
    }

    var systemImage: String {
        switch self {
        case .water: "drop"
        case .movement: "figure.walk"
        case .windDown: "moon.stars"
        }
    }
}

struct HabitsCard: View {
    let day: HabitDay?
    let unit: WaterUnit
    var focusedHabit: FocusState<HabitField?>.Binding
    let onSelect: (HabitField) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(HabitField.allCases) { field in
                    Button {
                        onSelect(field)
                    } label: {
                        HStack {
                            Label(field.title, systemImage: field.systemImage)
                                .fixedSize()
                            Spacer()
                            Text(value(for: field))
                                .lineLimit(1)
                                .foregroundStyle(isLogged(field) ? .primary : .secondary)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .focusable()
                    .focused(focusedHabit, equals: field)
                    .accessibilityLabel("\(field.title), \(value(for: field))")
                    .accessibilityHint("Opens the editor")
                    if field != .windDown { Divider() }
                }
                if let note = day?.note {
                    Divider()
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
                Text("Click a habit to log or edit it. Notes are optional.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            .padding(6)
        } label: {
            Label("Today's habits", systemImage: "checklist")
        }
    }

    private func isLogged(_ field: HabitField) -> Bool {
        switch field {
        case .water: day?.waterMilliliters != nil
        case .movement: day?.movementMinutes != nil
        case .windDown: day?.windDown != nil
        }
    }

    private func value(for field: HabitField) -> String {
        switch field {
        case .water: Display.water(day?.waterMilliliters, unit: unit)
        case .movement: Display.movement(day?.movementMinutes)
        case .windDown: Display.windDown(day?.windDown)
        }
    }
}
