import Charts
import SwiftData
import SwiftUI

enum TrendRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    var id: Int { rawValue }
    var label: String { self == .week ? "7 days" : "30 days" }
}

struct TrendsView: View {
    @Query private var sleep: [SleepEntry]
    @Query private var habitDays: [HabitDay]
    @AppStorage(PreferenceKey.waterUnit) private var waterUnitRaw = WaterUnit.milliliters.rawValue
    @Environment(\.theme) private var theme
    @State var range: TrendRange = .week

    var today: DayKey = .today()

    private var unit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .milliliters }

    var body: some View {
        let days = today.trailing(range.rawValue)
        let summaries = Trends.summaries(days: days, sleep: sleep, habits: habitDays)
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing) {
                ScreenHeader(title: "Trends", subtitle: "\(range.label) ending \(today.shortLabel)") {
                    Picker("Range", selection: $range) {
                        ForEach(TrendRange.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                    .labelsHidden()
                }

                Text("Days without an entry show as gaps. Averages use logged days only.")
                    .font(.callout)
                    .foregroundStyle(theme.muted)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: theme.spacing, alignment: .top)],
                          spacing: theme.spacing) {
                    ForEach(TrendMetric.allCases) { metric in
                        TrendCard(metric: metric, summary: summaries[metric]!, unit: unit, days: days)
                    }
                }
            }
            .padding(theme.screenPadding)
        }
        .background(theme.background)
        .navigationTitle("Trends")
        .hidesToolbarTitle()
    }
}

struct TrendCard: View {
    @Environment(\.theme) private var theme
    let metric: TrendMetric
    let summary: MetricSummary
    let unit: WaterUnit
    let days: [DayKey]

    private func plotted(_ value: Double) -> Double {
        switch metric {
        case .timeInBed, .estimatedSleep: value / 3600
        case .water: unit.fromMilliliters(value)
        default: value
        }
    }

    private var averageText: String {
        guard let average = summary.average else { return "No entries in this range" }
        switch metric {
        case .timeInBed, .estimatedSleep: return "Average \(DurationText.format(average))"
        case .quality: return "Average \(average.formatted(.number.precision(.fractionLength(1)))) / 5"
        case .water: return "Average \(unit.format(milliliters: average))"
        case .movement: return "Average \(Int(average.rounded())) min"
        case .windDown:
            let done = summary.points.filter { $0.value == 1 }.count
            return "Done on \(done) of \(summary.loggedCount) logged days"
        }
    }

    private var yLabel: String {
        switch metric {
        case .timeInBed, .estimatedSleep: "Hours"
        case .quality: "Quality"
        case .water: unit.symbol
        case .movement: "Minutes"
        case .windDown: "Done"
        }
    }

    private var yDomain: ClosedRange<Double> {
        switch metric {
        case .quality: return 0...5
        case .windDown: return 0...1
        default:
            let top = summary.points.compactMap(\.value).map(plotted).max() ?? 1
            return 0...max(top * 1.1, 1)
        }
    }

    private var axisDays: [String] {
        let stride = days.count > 7 ? 7 : 1
        return days.enumerated().filter { $0.offset % stride == 0 }.map(\.element.rawValue)
    }

    var body: some View {
        ThemePanel {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title)
                    .font(theme.heading(14))
                    .foregroundStyle(theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(averageText).font(theme.figure(20))
                Text(summary.loggedText).font(.caption).foregroundStyle(theme.muted)
                Chart {
                    ForEach(summary.points) { point in
                        if let value = point.value {
                            BarMark(
                                x: .value("Date", point.day.rawValue),
                                y: .value(yLabel, metric == .windDown ? 1 : plotted(value)))
                            .foregroundStyle(metric == .windDown && value == 0 ? theme.muted.opacity(0.45) : theme.accent)
                            .cornerRadius(theme.preset == .signal ? 1 : 3)
                        }
                    }
                }
                .chartXScale(domain: days.map(\.rawValue))
                .chartXAxis {
                    // Charts marks every date on this axis, so only the chosen
                    // dates draw a label; 30 labels would overlap.
                    let labeled = Set(axisDays)
                    AxisMarks(values: axisDays) { value in
                        if let raw = value.as(String.self), labeled.contains(raw), let day = DayKey(rawValue: raw) {
                            AxisGridLine().foregroundStyle(theme.line)
                            AxisValueLabel {
                                Text(days.count > 7 ? day.shortLabel : day.startDate().formatted(.dateTime.weekday(.narrow)))
                                    .foregroundStyle(theme.muted)
                            }
                        }
                    }
                }
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    if metric != .windDown {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(theme.line)
                            AxisValueLabel().foregroundStyle(theme.muted)
                        }
                    }
                }
                .chartYAxisLabel(position: .topLeading) {
                    Text(yLabel).font(.caption).foregroundStyle(theme.muted)
                }
                .frame(height: 120)
                .padding(.top, 8)
                .accessibilityLabel("\(metric.title) chart")
                .accessibilityValue("\(averageText). \(summary.loggedText).")
                if metric == .windDown {
                    Text("Bars: done (accent) or not done (gray). Gaps are not logged.")
                        .font(.caption).foregroundStyle(theme.muted)
                }
            }
        }
    }
}
