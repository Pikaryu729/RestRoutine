import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var navigation: AppNavigation
    /// Overrides the current date, for previews and tests.
    var today: DayKey?

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $navigation.selection)
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch navigation.selection ?? .today {
            case .today: TodayView(today: today ?? .today())
            case .history: HistoryView(today: today ?? .today())
            case .trends: TrendsView(today: today ?? .today())
            }
        }
        .themeRoot()
    }
}

struct Sidebar: View {
    @Environment(\.theme) private var theme
    @Environment(\.openSettings) private var openSettings
    @Binding var selection: Destination?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "moon")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                Text("Rest & Routine")
                    .font(theme.heading(17))
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 18)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(Destination.allCases) { destination in
                Button {
                    selection = destination
                } label: {
                    Label(destination.title, systemImage: destination.systemImage)
                }
                .buttonStyle(SidebarItemStyle(selected: (selection ?? .today) == destination))
                .accessibilityAddTraits((selection ?? .today) == destination ? .isSelected : [])
            }

            Spacer(minLength: 24)

            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(SidebarItemStyle(selected: false))
            .help("Open Settings (⌘,)")

            Text("Manual entries.\nOnly on your Mac.")
                .font(.caption)
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 10)
                .padding(.top, 10)
        }
        .padding(.horizontal, 10)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.sidebar)
    }
}

private struct SidebarItemStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Item(configuration: configuration, selected: selected)
    }

    private struct Item: View {
        @Environment(\.theme) private var theme
        let configuration: Configuration
        let selected: Bool

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: theme.preset == .studio ? 14 : theme.controlRadius)
            configuration.label
                .labelStyle(SidebarLabelStyle())
                .font(.body.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? theme.onAccent : theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shape.fill(selected ? theme.accent : configuration.isPressed ? theme.tint : .clear))
                .contentShape(shape)
        }
    }
}

private struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 9) {
            configuration.icon.frame(width: 20)
            configuration.title
        }
    }
}
