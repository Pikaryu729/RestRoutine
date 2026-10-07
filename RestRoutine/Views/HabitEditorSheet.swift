import SwiftData
import SwiftUI

struct HabitEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @AppStorage(PreferenceKey.waterUnit) private var waterUnitRaw = WaterUnit.milliliters.rawValue

    let dateKey: DayKey
    var initialFocus: HabitField?
    /// Prefills the editor instead of loading the saved values, for previews and tests.
    var initialDraft: HabitDraft?

    @State private var draft = HabitDraft()
    @State private var loaded = false
    @State private var saveError: String?
    @FocusState private var focus: HabitField?

    private var unit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .milliliters }
    private var store: JournalStore { JournalStore(context: context) }

    private var waterError: String? {
        do { _ = try HabitParsing.water(draft.waterText, unit: unit); return nil } catch { return error.localizedDescription }
    }

    private var movementError: String? {
        do { _ = try HabitParsing.movement(draft.movementText); return nil } catch { return error.localizedDescription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Habits")
                        .font(theme.heading(22))
                        .accessibilityAddTraits(.isHeader)
                    Text(dateKey.longLabel).foregroundStyle(theme.muted)
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        EditorLabel("Water (\(unit.symbol))")
                        TextField("Water (\(unit.symbol))", text: $draft.waterText, prompt: Text("Not logged"))
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .water)
                    }
                    if let waterError {
                        GridRow {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            Text(waterError).foregroundStyle(theme.danger).font(.callout)
                        }
                    }
                    GridRow {
                        EditorLabel("Movement (minutes)")
                        TextField("Movement (minutes)", text: $draft.movementText, prompt: Text("Not logged"))
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .movement)
                    }
                    if let movementError {
                        GridRow {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            Text(movementError).foregroundStyle(theme.danger).font(.callout)
                        }
                    }
                    GridRow {
                        EditorLabel("Wind-down")
                        Picker("Wind-down", selection: $draft.windDown) {
                            Text("Not logged").tag(WindDown?.none)
                            Text("Done").tag(WindDown?.some(.done))
                            Text("Not done").tag(WindDown?.some(.notDone))
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .focused($focus, equals: .windDown)
                    }
                    GridRow(alignment: .top) {
                        EditorLabel("Note (optional)")
                        TextField("Note (optional)", text: $draft.note, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Leave a field blank to keep it Not logged. Zero is saved as zero.")
                        .foregroundStyle(theme.muted)
                    if let saveError { Text(saveError).foregroundStyle(theme.danger) }
                }
                .font(.callout)
            }
            .padding(22)

            ThemeRule()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.themed())
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.themed(.primary))
                    .disabled(waterError != nil || movementError != nil)
            }
            .padding(16)
        }
        .background(theme.surface)
        .frame(width: 440)
        .navigationTitle("Habits")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = initialDraft ?? HabitDraft(day: try? store.habitDay(dateKey: dateKey.rawValue), unit: unit)
            focus = initialFocus
        }
    }

    private func save() {
        do {
            try store.saveHabits(draft, dateKey: dateKey.rawValue, unit: unit)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
