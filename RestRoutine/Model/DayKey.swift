import Foundation

/// A local calendar date stored as "yyyy-MM-dd".
struct DayKey: Hashable, Comparable, Identifiable, Codable {
    let rawValue: String

    var id: String { rawValue }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day), year > 0
        else { return nil }
        self.rawValue = String(format: "%04d-%02d-%02d", year, month, day)
    }

    init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func today(now: Date = .now, timeZone: TimeZone = .current) -> DayKey {
        DayKey(date: now, timeZone: timeZone)
    }

    var components: DateComponents {
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Start of this date in the given calendar's time zone.
    func startDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: components) ?? .now
    }

    /// The date at a given local hour and minute.
    func date(hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        var c = components
        c.hour = hour
        c.minute = minute
        return calendar.date(from: c) ?? .now
    }

    func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let base = utc.date(from: components) ?? .now
        let moved = utc.date(byAdding: .day, value: days, to: base) ?? base
        return DayKey(date: moved, timeZone: utc.timeZone)
    }

    /// The last `count` dates ending with (and including) this one, oldest first.
    func trailing(_ count: Int) -> [DayKey] {
        (0..<count).reversed().map { adding(days: -$0) }
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }

    var longLabel: String { startDate().formatted(date: .complete, time: .omitted) }
    var mediumLabel: String { startDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    var shortLabel: String { startDate().formatted(.dateTime.month(.abbreviated).day()) }
}
