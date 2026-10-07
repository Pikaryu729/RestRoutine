import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var navigation: AppNavigation
    /// Overrides the current date, for previews and tests.
    var today: DayKey?

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $navigation.selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch navigation.selection ?? .today {
            case .today: TodayView(today: today ?? .today())
            case .history: HistoryView(today: today ?? .today())
            case .trends: TrendsView(today: today ?? .today())
            }
        }
    }
}
