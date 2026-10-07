import SwiftData
import SwiftUI

struct HabitEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
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
            Form {
                Section {
                    TextField("Water (\(unit.symbol))", text: $draft.waterText, prompt: Text("Not logged"))
                        .focused($focus, equals: .water)
                    if let waterError { Text(waterError).foregroundStyle(.red).font(.callout) }
                    TextField("Movement (minutes)", text: $draft.movementText, prompt: Text("Not logged"))
                        .focused($focus, equals: .movement)
                    if let movementError { Text(movementError).foregroundStyle(.red).font(.callout) }
                    Picker("Wind-down", selection: $draft.windDown) {
                        Text("Not logged").tag(WindDown?.none)
                        Text("Done").tag(WindDown?.some(.done))
                        Text("Not done").tag(WindDown?.some(.notDone))
                    }
                    .pickerStyle(.segmented)
                    .focused($focus, equals: .windDown)
                    TextField("Note (optional)", text: $draft.note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text(dateKey.longLabel)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Leave a field blank to keep it Not logged. Zero is saved as zero.")
                            .foregroundStyle(.secondary)
                        if let saveError { Text(saveError).foregroundStyle(.red) }
                    }
                    .font(.callout)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(waterError != nil || movementError != nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
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
