import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var navigation: AppNavigation
    @Query(sort: \SleepEntry.end, order: .reverse) private var sleep: [SleepEntry]
    @Query private var habitDays: [HabitDay]
    @AppStorage(PreferenceKey.waterUnit) private var waterUnitRaw = WaterUnit.milliliters.rawValue
    @Environment(\.theme) private var theme
    @State private var sleepSheet: SleepSheetRequest?
    @State private var habitEditor: HabitField?
    @FocusState private var focusedHabit: HabitField?

    /// Overrides the current date, for previews and tests.
    var today: DayKey = .today()

    private var unit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .milliliters }
    private var todayHabits: HabitDay? { habitDays.first { $0.dateKey == today.rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing + 6) {
                ScreenHeader(title: "Today", subtitle: today.startDate().formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                    Button {
                        sleepSheet = .new(today)
                    } label: {
                        Label("Log sleep", systemImage: "bed.double")
                    }
                    .buttonStyle(.themed(.primary))
                    .help("Log sleep (⌘L)")
                }

                HStack(alignment: .top, spacing: theme.spacing) {
                    SleepSummaryCard(entry: sleep.first) { entry in
                        sleepSheet = .edit(entry.id)
                    } onLog: {
                        sleepSheet = .new(today)
                    }
                    .frame(minWidth: 250, maxWidth: .infinity, alignment: .topLeading)

                    HabitsCard(
                        day: todayHabits, unit: unit, focusedHabit: $focusedHabit,
                        onSelect: { habitEditor = $0 })
                    .frame(minWidth: 250, maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(theme.screenPadding)
        }
        .background(theme.background)
        .navigationTitle("Today · \(today.shortLabel)")
        .hidesToolbarTitle()
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
    @Environment(\.theme) private var theme
    let entry: SleepEntry?
    let onEdit: (SleepEntry) -> Void
    let onLog: () -> Void

    var body: some View {
        ThemePanel(title: "Last sleep") {
            if let entry {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Kicker("Estimated sleep")
                        if let estimate = entry.estimatedSleep {
                            Text(DurationText.format(estimate)).font(theme.figure(34))
                        } else {
                            Text("Unavailable").font(theme.figure(24)).foregroundStyle(theme.muted)
                        }
                        Text("Woke \(DayKey(rawValue: entry.wakeDateKey)?.mediumLabel ?? entry.wakeDateKey)")
                            .font(.callout)
                            .foregroundStyle(theme.muted)
                    }
                    .padding(theme.preset == .studio ? 16 : 0)
                    .padding(.vertical, theme.preset == .studio ? 0 : 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if theme.preset == .studio {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.tint)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    if entry.estimatedSleep == nil {
                        Text("Add awake minutes to estimate sleep. Time in bed is not the same as sleep.")
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                            .padding(.top, 8)
                    }
                    Text(Display.timeRange(entry))
                        .font(.callout)
                        .foregroundStyle(theme.muted)
                        .padding(.vertical, 12)
                    ThemeLine("Time in bed", DurationText.format(entry.timeInBed))
                    ThemeLine("Awake", entry.awakeMinutes.map { "\($0) min" } ?? "Not entered",
                              muted: entry.awakeMinutes == nil)
                    ThemeLine("Quality", Display.quality(entry.quality), muted: entry.quality == nil)
                    ThemeLine("Source", entry.sourceLabel)
                    if let note = entry.note {
                        Text(note).font(.callout).foregroundStyle(theme.muted).padding(.top, 6)
                    }
                    Button("Edit sleep") { onEdit(entry) }
                        .buttonStyle(.themed())
                        .padding(.top, 12)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No sleep logged yet").font(theme.heading(22))
                    Text("Log when you went to bed and when you woke up.")
                        .foregroundStyle(theme.muted)
                    Button("Log sleep", action: onLog)
                        .buttonStyle(.themed(.primary))
                        .padding(.top, 6)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "moon.stars")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(theme.muted)
                .padding(theme.panelPadding)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
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
    @Environment(\.theme) private var theme
    let day: HabitDay?
    let unit: WaterUnit
    var focusedHabit: FocusState<HabitField?>.Binding
    let onSelect: (HabitField) -> Void

    var body: some View {
        ThemePanel(title: "Today's habits") {
            ForEach(HabitField.allCases) { field in
                if field != .water { ThemeRule() }
                Button {
                    onSelect(field)
                } label: {
                    HStack(spacing: 12) {
                        HabitIcon(systemImage: field.systemImage)
                        Text(field.title)
                            .fixedSize()
                        Spacer(minLength: 8)
                        Text(value(for: field))
                            .font(theme.value.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(isLogged(field) ? theme.ink : theme.muted)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.muted)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -6)
                .focusable()
                .focused(focusedHabit, equals: field)
                .accessibilityLabel("\(field.title), \(value(for: field))")
                .accessibilityHint("Opens the editor")
            }
            if let note = day?.note {
                ThemeRule()
                Text(note).font(.callout).foregroundStyle(theme.muted).padding(.vertical, 8)
            }
            ThemeRule().padding(.top, 6)
            Text("Click a habit to log or edit it. Notes are optional.")
                .font(.caption)
                .foregroundStyle(theme.muted)
                .padding(.top, 10)
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

/// A habit's symbol in a soft block (Soft studio) or an outlined circle.
struct HabitIcon: View {
    @Environment(\.theme) private var theme
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15))
            .foregroundStyle(theme.preset == .studio ? theme.accent : theme.muted)
            .frame(width: 32, height: 32)
            .background {
                if theme.preset == .studio {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(theme.tint)
                } else {
                    Circle().strokeBorder(theme.line, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}
