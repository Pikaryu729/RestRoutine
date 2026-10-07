import Foundation

enum Destination: String, CaseIterable, Identifiable, Hashable {
    case today, history, trends
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .trends: "Trends"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .history: "calendar"
        case .trends: "chart.bar.xaxis"
        }
    }
}

/// Shared navigation state, so reminder activations can open the right place.
@MainActor
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()

    @Published var selection: Destination? = .today
    /// Incremented to ask Today to open the sleep sheet.
    @Published var sleepEntryRequest = 0
    /// Incremented to ask Today to focus the wind-down habit.
    @Published var windDownFocusRequest = 0

    func handleReminder(_ kind: ReminderKind) {
        selection = .today
        switch kind {
        case .morning: sleepEntryRequest += 1
        case .evening: windDownFocusRequest += 1
        }
    }
}
