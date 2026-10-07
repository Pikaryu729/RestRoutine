import Foundation

enum SleepValidationError: Error, Equatable, LocalizedError {
    case endNotAfterStart
    case awakeMinutesNotWholeNumber
    case awakeMinutesOutOfRange(maximum: Int)
    case qualityOutOfRange

    var errorDescription: String? {
        switch self {
        case .endNotAfterStart:
            "Wake time must be after bedtime."
        case .awakeMinutesNotWholeNumber:
            "Awake minutes must be a whole number of minutes."
        case .awakeMinutesOutOfRange(let maximum):
            "Awake minutes must be between 0 and \(maximum)."
        case .qualityOutOfRange:
            "Quality must be from 1 to 5."
        }
    }
}

enum SleepMath {
    /// Elapsed time between two instants. Using instants rather than wall-clock
    /// times keeps the result correct across daylight-saving changes.
    static func timeInBed(start: Date, end: Date) -> TimeInterval {
        end.timeIntervalSince(start)
    }

    /// Time in bed minus supplied awake minutes. Without awake minutes there
    /// is no estimate; time in bed is not sleep.
    static func estimatedSleep(start: Date, end: Date, awakeMinutes: Int?) -> TimeInterval? {
        guard let awakeMinutes else { return nil }
        return max(0, timeInBed(start: start, end: end) - TimeInterval(awakeMinutes * 60))
    }

    static func wakeDateKey(end: Date, timeZoneIdentifier: String) -> String {
        DayKey(date: end, timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current).rawValue
    }

    /// Largest number of awake minutes the interval allows.
    static func maximumAwakeMinutes(start: Date, end: Date) -> Int {
        max(0, Int(timeInBed(start: start, end: end) / 60))
    }

    static func validate(start: Date, end: Date, awakeMinutes: Int?, quality: Int?) throws {
        guard end > start else { throw SleepValidationError.endNotAfterStart }
        if let awakeMinutes {
            let maximum = maximumAwakeMinutes(start: start, end: end)
            guard (0...maximum).contains(awakeMinutes) else {
                throw SleepValidationError.awakeMinutesOutOfRange(maximum: maximum)
            }
        }
        if let quality, !(1...5).contains(quality) {
            throw SleepValidationError.qualityOutOfRange
        }
    }

    /// Parses the awake-minutes field. Blank means not supplied.
    static func parseAwakeMinutes(_ text: String) throws -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let value = Int(trimmed) else { throw SleepValidationError.awakeMinutesNotWholeNumber }
        return value
    }
}

enum DurationText {
    /// Formats a duration as "7h 30m", "8h" or "45m".
    static func format(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((interval / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, let m): return "\(m)m"
        case (let h, 0): return "\(h)h"
        default: return "\(hours)h \(minutes)m"
        }
    }
}
