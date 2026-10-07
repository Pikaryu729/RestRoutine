import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([SleepEntry.self, HabitDay.self])

    /// ~/Library/Containers/com.example.RestRoutine/Data/Library/Application Support/RestRoutine/
    /// when sandboxed. The database and its companion files live here.
    static func storeDirectory(fileManager: FileManager = .default) throws -> URL {
        #if DEBUG
        // A disposable store for development and verification runs, so sample
        // data never touches the real journal.
        if let name = UserDefaults.standard.string(forKey: "RRDisposableStore"), !name.isEmpty {
            let url = fileManager.temporaryDirectory
                .appendingPathComponent("RestRoutineDisposable", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        #endif
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = base.appendingPathComponent("RestRoutine", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let url = try storeDirectory().appendingPathComponent("RestRoutine.store")
            configuration = ModelConfiguration(schema: schema, url: url)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
