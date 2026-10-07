import Foundation
import SwiftData

/// Values from the sleep sheet before they are saved.
struct SleepDraft: Equatable {
    var start: Date
    var end: Date
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var awakeMinutesText: String = ""
    var quality: Int?
    var note: String = ""

    /// The default new entry: 11:00 PM the night before to 7:00 AM on the wake date.
    static func defaultFor(wakeDate: DayKey, calendar: Calendar = .current) -> SleepDraft {
        SleepDraft(
            start: wakeDate.adding(days: -1).date(hour: 23, minute: 0, calendar: calendar),
            end: wakeDate.date(hour: 7, minute: 0, calendar: calendar),
            timeZoneIdentifier: calendar.timeZone.identifier)
    }

    init(start: Date, end: Date, timeZoneIdentifier: String = TimeZone.current.identifier,
         awakeMinutesText: String = "", quality: Int? = nil, note: String = "") {
        self.start = start
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
        self.awakeMinutesText = awakeMinutesText
        self.quality = quality
        self.note = note
    }

    init(entry: SleepEntry) {
        start = entry.start
        end = entry.end
        timeZoneIdentifier = entry.timeZoneIdentifier
        awakeMinutesText = entry.awakeMinutes.map(String.init) ?? ""
        quality = entry.quality
        note = entry.note ?? ""
    }

    var wakeDateKey: String { SleepMath.wakeDateKey(end: end, timeZoneIdentifier: timeZoneIdentifier) }

    /// Validated awake minutes, or the first problem with the draft.
    func validated() throws -> Int? {
        let awake = try SleepMath.parseAwakeMinutes(awakeMinutesText)
        try SleepMath.validate(start: start, end: end, awakeMinutes: awake, quality: quality)
        return awake
    }
}

/// Values from a habit editor before they are saved.
struct HabitDraft: Equatable {
    var waterText: String = ""
    var movementText: String = ""
    var windDown: WindDown?
    var note: String = ""

    init(waterText: String = "", movementText: String = "", windDown: WindDown? = nil, note: String = "") {
        self.waterText = waterText
        self.movementText = movementText
        self.windDown = windDown
        self.note = note
    }

    init(day: HabitDay?, unit: WaterUnit) {
        waterText = day?.waterMilliliters.map { unit.editText(milliliters: $0) } ?? ""
        movementText = day?.movementMinutes.map(String.init) ?? ""
        windDown = day?.windDown
        note = day?.note ?? ""
    }
}

enum SleepSaveError: Error, Equatable {
    case invalid(SleepValidationError)
    case duplicateWakeDate(existingID: UUID, wakeDateKey: String)
}

/// Reads and writes journal records through a model context.
struct JournalStore {
    let context: ModelContext

    func allSleep() throws -> [SleepEntry] {
        try context.fetch(FetchDescriptor<SleepEntry>(sortBy: [SortDescriptor(\.end, order: .reverse)]))
    }

    func allHabitDays() throws -> [HabitDay] {
        try context.fetch(FetchDescriptor<HabitDay>(sortBy: [SortDescriptor(\.dateKey, order: .reverse)]))
    }

    func latestSleep() throws -> SleepEntry? {
        var descriptor = FetchDescriptor<SleepEntry>(sortBy: [SortDescriptor(\.end, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func sleepEntry(wakeDateKey key: String) throws -> SleepEntry? {
        var descriptor = FetchDescriptor<SleepEntry>(predicate: #Predicate { $0.wakeDateKey == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func sleepEntry(id: UUID) throws -> SleepEntry? {
        var descriptor = FetchDescriptor<SleepEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func habitDay(dateKey key: String) throws -> HabitDay? {
        var descriptor = FetchDescriptor<HabitDay>(predicate: #Predicate { $0.dateKey == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Saves a new entry, or updates `editing`. A new entry for a wake date that
    /// already has one is refused so the caller can offer editing instead.
    @discardableResult
    func saveSleep(_ draft: SleepDraft, editing: SleepEntry? = nil, now: Date = .now) throws -> SleepEntry {
        let awake: Int?
        do {
            awake = try draft.validated()
        } catch let error as SleepValidationError {
            throw SleepSaveError.invalid(error)
        }
        let key = draft.wakeDateKey
        if let existing = try sleepEntry(wakeDateKey: key), existing.id != editing?.id {
            throw SleepSaveError.duplicateWakeDate(existingID: existing.id, wakeDateKey: key)
        }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry: SleepEntry
        if let editing {
            entry = editing
            entry.start = draft.start
            entry.end = draft.end
            entry.timeZoneIdentifier = draft.timeZoneIdentifier
            entry.wakeDateKey = key
            entry.awakeMinutes = awake
            entry.quality = draft.quality
            entry.note = note.isEmpty ? nil : note
            entry.updatedAt = now
        } else {
            entry = SleepEntry(
                start: draft.start, end: draft.end, timeZoneIdentifier: draft.timeZoneIdentifier,
                awakeMinutes: awake, quality: draft.quality, note: note.isEmpty ? nil : note,
                createdAt: now, updatedAt: now)
            context.insert(entry)
        }
        try context.save()
        return entry
    }

    /// Saves habits for a date. Blank fields stay "Not logged".
    @discardableResult
    func saveHabits(_ draft: HabitDraft, dateKey: String, unit: WaterUnit, now: Date = .now) throws -> HabitDay? {
        let water = try HabitParsing.water(draft.waterText, unit: unit)
        let movement = try HabitParsing.movement(draft.movementText)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = try habitDay(dateKey: dateKey) ?? {
            let new = HabitDay(dateKey: dateKey)
            context.insert(new)
            return new
        }()
        day.waterMilliliters = water
        day.movementMinutes = movement
        day.windDown = draft.windDown
        day.note = note.isEmpty ? nil : note
        day.updatedAt = now
        if day.isEmpty {
            context.delete(day)
            try context.save()
            return nil
        }
        try context.save()
        return day
    }

    func deleteSleep(_ entry: SleepEntry) throws {
        context.delete(entry)
        try context.save()
    }

    func deleteHabits(dateKey: String) throws {
        if let day = try habitDay(dateKey: dateKey) {
            context.delete(day)
            try context.save()
        }
    }

    /// Removes every app record. Unsaved work is discarded if this fails.
    func deleteAll() throws {
        do {
            for entry in try allSleep() { context.delete(entry) }
            for day in try allHabitDays() { context.delete(day) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
