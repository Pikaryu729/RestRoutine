import Foundation

enum Display {
    static func water(_ milliliters: Double?, unit: WaterUnit) -> String {
        milliliters.map { unit.format(milliliters: $0) } ?? "Not logged"
    }

    static func movement(_ minutes: Int?) -> String {
        minutes.map { "\($0) min" } ?? "Not logged"
    }

    static func windDown(_ value: WindDown?) -> String {
        value?.label ?? "Not logged"
    }

    static func quality(_ value: Int?) -> String {
        value.map { "\($0) / 5" } ?? "Not rated"
    }

    static func timeRange(_ entry: SleepEntry) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: entry.timeZone)
        return "\(entry.start.formatted(style)) – \(entry.end.formatted(style))"
    }
}
