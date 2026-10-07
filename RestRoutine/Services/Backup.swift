import Foundation
import SwiftData

struct BackupFile: Codable, Equatable {
    static let formatIdentifier = "com.example.RestRoutine.backup"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var sleepEntries: [SleepRecord]
    var habitDays: [HabitRecord]
    var preferences: PreferencesRecord

    struct SleepRecord: Codable, Equatable {
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
    }

    struct HabitRecord: Codable, Equatable {
        var id: UUID
        var dateKey: String
        var waterMilliliters: Double?
        var movementMinutes: Int?
        var windDown: String?
        var note: String?
        var updatedAt: Date
    }

    struct PreferencesRecord: Codable, Equatable {
        var waterUnit: String
        var morningReminder: ReminderSetting
        var eveningReminder: ReminderSetting
    }
}

enum BackupError: Error, Equatable, LocalizedError {
    case unreadable
    case notABackup
    case unsupportedVersion(Int)
    case invalidRecord(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: "The file is not a readable Rest & Routine backup."
        case .notABackup: "The file is not a Rest & Routine backup."
        case .unsupportedVersion(let v): "This backup uses version \(v), which this app cannot read."
        case .invalidRecord(let detail): "The backup contains an invalid record: \(detail)"
        }
    }
}

enum BackupService {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// A full snapshot of all records and preferences.
    static func makeBackup(store: JournalStore, defaults: UserDefaults, reminders: [ReminderKind: ReminderSetting],
                           now: Date = .now) throws -> BackupFile {
        let sleep = try store.allSleep().sorted { $0.start < $1.start }.map {
            BackupFile.SleepRecord(
                id: $0.id, start: $0.start, end: $0.end, timeZoneIdentifier: $0.timeZoneIdentifier,
                wakeDateKey: $0.wakeDateKey, awakeMinutes: $0.awakeMinutes, quality: $0.quality, note: $0.note,
                source: $0.source, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
        let habits = try store.allHabitDays().sorted { $0.dateKey < $1.dateKey }.map {
            BackupFile.HabitRecord(
                id: $0.id, dateKey: $0.dateKey, waterMilliliters: $0.waterMilliliters,
                movementMinutes: $0.movementMinutes, windDown: $0.windDownRaw, note: $0.note, updatedAt: $0.updatedAt)
        }
        return BackupFile(
            format: BackupFile.formatIdentifier, version: BackupFile.currentVersion, exportedAt: now,
            sleepEntries: sleep, habitDays: habits,
            preferences: .init(
                waterUnit: defaults.waterUnit.rawValue,
                morningReminder: reminders[.morning] ?? .defaults(for: .morning),
                eveningReminder: reminders[.evening] ?? .defaults(for: .evening)))
    }

    static func encode(_ file: BackupFile) throws -> Data {
        try encoder().encode(file)
    }

    /// Decodes and validates the whole file before anything is changed.
    static func validate(_ data: Data) throws -> BackupFile {
        struct Header: Decodable { var format: String?; var version: Int? }
        guard let header = try? decoder().decode(Header.self, from: data) else { throw BackupError.unreadable }
        guard header.format == BackupFile.formatIdentifier else { throw BackupError.notABackup }
        guard header.version == BackupFile.currentVersion else {
            throw BackupError.unsupportedVersion(header.version ?? 0)
        }
        let file: BackupFile
        do {
            file = try decoder().decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.unreadable
        }

        var ids = Set<UUID>()
        var wakeKeys = Set<String>()
        for record in file.sleepEntries {
            guard ids.insert(record.id).inserted else { throw BackupError.invalidRecord("a sleep entry is repeated.") }
            guard TimeZone(identifier: record.timeZoneIdentifier) != nil else {
                throw BackupError.invalidRecord("a sleep entry has an unknown time zone.")
            }
            do {
                try SleepMath.validate(
                    start: record.start, end: record.end, awakeMinutes: record.awakeMinutes, quality: record.quality)
            } catch let error as SleepValidationError {
                throw BackupError.invalidRecord("sleep for \(record.wakeDateKey): \(error.localizedDescription)")
            }
            let key = SleepMath.wakeDateKey(end: record.end, timeZoneIdentifier: record.timeZoneIdentifier)
            guard key == record.wakeDateKey else {
                throw BackupError.invalidRecord("a sleep entry's wake date does not match its wake time.")
            }
            guard record.source == SleepEntry.manualSource else {
                throw BackupError.invalidRecord("a sleep entry has an unsupported source.")
            }
            guard wakeKeys.insert(key).inserted else {
                throw BackupError.invalidRecord("more than one sleep entry for \(key).")
            }
        }

        var dateKeys = Set<String>()
        for record in file.habitDays {
            guard ids.insert(record.id).inserted else { throw BackupError.invalidRecord("a habit day is repeated.") }
            guard let key = DayKey(rawValue: record.dateKey), key.rawValue == record.dateKey else {
                throw BackupError.invalidRecord("a habit day has an invalid date.")
            }
            guard dateKeys.insert(record.dateKey).inserted else {
                throw BackupError.invalidRecord("more than one habit day for \(record.dateKey).")
            }
            if let water = record.waterMilliliters, !(water.isFinite && water >= 0) {
                throw BackupError.invalidRecord("water for \(record.dateKey) must be zero or more.")
            }
            if let movement = record.movementMinutes, movement < 0 {
                throw BackupError.invalidRecord("movement for \(record.dateKey) must be zero or more.")
            }
            if let raw = record.windDown, WindDown(rawValue: raw) == nil {
                throw BackupError.invalidRecord("wind-down for \(record.dateKey) is not recognised.")
            }
        }

        guard WaterUnit(rawValue: file.preferences.waterUnit) != nil else {
            throw BackupError.invalidRecord("the water unit is not recognised.")
        }
        for setting in [file.preferences.morningReminder, file.preferences.eveningReminder] {
            guard (0...23).contains(setting.hour), (0...59).contains(setting.minute) else {
                throw BackupError.invalidRecord("a reminder time is not valid.")
            }
        }
        return file
    }

    /// Replaces every record in one save. If anything fails, the context is
    /// rolled back and the existing records stay as they were.
    static func restore(_ file: BackupFile, into context: ModelContext) throws {
        do {
            for entry in try context.fetch(FetchDescriptor<SleepEntry>()) { context.delete(entry) }
            for day in try context.fetch(FetchDescriptor<HabitDay>()) { context.delete(day) }
            for r in file.sleepEntries {
                context.insert(SleepEntry(
                    id: r.id, start: r.start, end: r.end, timeZoneIdentifier: r.timeZoneIdentifier,
                    awakeMinutes: r.awakeMinutes, quality: r.quality, note: r.note, source: r.source,
                    createdAt: r.createdAt, updatedAt: r.updatedAt))
            }
            for r in file.habitDays {
                context.insert(HabitDay(
                    id: r.id, dateKey: r.dateKey, waterMilliliters: r.waterMilliliters,
                    movementMinutes: r.movementMinutes, windDown: r.windDown.flatMap(WindDown.init(rawValue:)),
                    note: r.note, updatedAt: r.updatedAt))
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func suggestedFileName(now: Date = .now) -> String {
        "Rest & Routine Backup \(DayKey(date: now).rawValue).json"
    }
}
