import Foundation
import SwiftData
@testable import RestRoutine

enum TestSupport {
    static let chicago = TimeZone(identifier: "America/Chicago")!

    static func calendar(_ zone: TimeZone = chicago) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, zone: TimeZone = chicago) -> Date {
        calendar(zone).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Contexts crash if their container is released, so tests keep them alive here.
    @MainActor private static var retained: [ModelContainer] = []

    @MainActor
    static func inMemoryStore() throws -> (ModelContainer, JournalStore) {
        let container = try Persistence.makeContainer(inMemory: true)
        retained.append(container)
        return (container, JournalStore(context: container.mainContext))
    }
}
