import Foundation
import SwiftData

/// One manual sleep entry. It belongs to the local date of its wake time,
/// measured in the time zone captured when it was saved.
@Model
final class SleepEntry {
    var id: UUID
    var start: Date
    var end: Date
    var timeZoneIdentifier: String
    var wakeDateKey: String
    var awakeMinutes: Int?
    var quality: Int?
    var note: String?
    var source: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        timeZoneIdentifier: String,
        awakeMinutes: Int? = nil,
        quality: Int? = nil,
        note: String? = nil,
        source: String = SleepEntry.manualSource,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
        self.wakeDateKey = SleepMath.wakeDateKey(end: end, timeZoneIdentifier: timeZoneIdentifier)
        self.awakeMinutes = awakeMinutes
        self.quality = quality
        self.note = note
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static let manualSource = "manual"

    var timeInBed: TimeInterval { SleepMath.timeInBed(start: start, end: end) }

    var estimatedSleep: TimeInterval? {
        SleepMath.estimatedSleep(start: start, end: end, awakeMinutes: awakeMinutes)
    }

    var sourceLabel: String {
        source == SleepEntry.manualSource ? "Manual entry" : source
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
}

enum WindDown: String, Codable, CaseIterable, Identifiable {
    case done
    case notDone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .done: "Done"
        case .notDone: "Not done"
        }
    }
}

/// The everyday habits for one local calendar date. A nil value means
/// "Not logged", which is different from zero or "Not done".
@Model
final class HabitDay {
    var id: UUID
    var dateKey: String
    var waterMilliliters: Double?
    var movementMinutes: Int?
    var windDownRaw: String?
    var note: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        dateKey: String,
        waterMilliliters: Double? = nil,
        movementMinutes: Int? = nil,
        windDown: WindDown? = nil,
        note: String? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.dateKey = dateKey
        self.waterMilliliters = waterMilliliters
        self.movementMinutes = movementMinutes
        self.windDownRaw = windDown?.rawValue
        self.note = note
        self.updatedAt = updatedAt
    }

    var windDown: WindDown? {
        get { windDownRaw.flatMap(WindDown.init(rawValue:)) }
        set { windDownRaw = newValue?.rawValue }
    }

    /// True when nothing at all is recorded for the date.
    var isEmpty: Bool {
        waterMilliliters == nil && movementMinutes == nil && windDownRaw == nil
            && (note ?? "").isEmpty
    }
}
