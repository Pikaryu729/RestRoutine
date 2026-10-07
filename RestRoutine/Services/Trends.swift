import Foundation

struct DailyPoint: Identifiable, Equatable {
    let day: DayKey
    let value: Double?
    var id: String { day.rawValue }
}

struct MetricSummary: Equatable {
    let points: [DailyPoint]
    var totalDays: Int { points.count }
    var loggedCount: Int { points.filter { $0.value != nil }.count }
    /// Average of logged days only. Missing days are excluded, never counted as zero.
    var average: Double? {
        let values = points.compactMap(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    var loggedText: String { "\(loggedCount) of \(totalDays) days logged" }
}

enum TrendMetric: String, CaseIterable, Identifiable {
    case timeInBed, estimatedSleep, quality, water, movement, windDown
    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeInBed: "Time in bed"
        case .estimatedSleep: "Estimated sleep"
        case .quality: "Sleep quality"
        case .water: "Water"
        case .movement: "Movement"
        case .windDown: "Wind-down"
        }
    }
}

enum Trends {
    static func summarize(days: [DayKey], values: [String: Double]) -> MetricSummary {
        MetricSummary(points: days.map { DailyPoint(day: $0, value: values[$0.rawValue]) })
    }

    /// Per-day values for each metric over the given dates.
    static func summaries(days: [DayKey], sleep: [SleepEntry], habits: [HabitDay]) -> [TrendMetric: MetricSummary] {
        var bed: [String: Double] = [:]
        var estimate: [String: Double] = [:]
        var quality: [String: Double] = [:]
        for entry in sleep {
            bed[entry.wakeDateKey] = entry.timeInBed
            if let e = entry.estimatedSleep { estimate[entry.wakeDateKey] = e }
            if let q = entry.quality { quality[entry.wakeDateKey] = Double(q) }
        }
        var water: [String: Double] = [:]
        var movement: [String: Double] = [:]
        var windDown: [String: Double] = [:]
        for day in habits {
            if let w = day.waterMilliliters { water[day.dateKey] = w }
            if let m = day.movementMinutes { movement[day.dateKey] = Double(m) }
            if let d = day.windDown { windDown[day.dateKey] = d == .done ? 1 : 0 }
        }
        return [
            .timeInBed: summarize(days: days, values: bed),
            .estimatedSleep: summarize(days: days, values: estimate),
            .quality: summarize(days: days, values: quality),
            .water: summarize(days: days, values: water),
            .movement: summarize(days: days, values: movement),
            .windDown: summarize(days: days, values: windDown),
        ]
    }
}
