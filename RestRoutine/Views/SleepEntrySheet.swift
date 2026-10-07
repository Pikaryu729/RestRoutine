import SwiftData
import SwiftUI

enum SleepSheetRequest: Identifiable, Hashable {
    case new(DayKey)
    case edit(UUID)

    var id: String {
        switch self {
        case .new(let day): "new-\(day.rawValue)"
        case .edit(let id): "edit-\(id.uuidString)"
        }
    }
}

struct SleepEntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let request: SleepSheetRequest

    @State private var draft: SleepDraft
    @State private var editingID: UUID?
    @State private var duplicate: (id: UUID, key: String)?
    @State private var saveError: String?
    @State private var loaded = false

    /// `initialDraft` prefills a new entry, for previews and tests.
    init(request: SleepSheetRequest, initialDraft: SleepDraft? = nil) {
        self.request = request
        switch request {
        case .new(let day):
            _draft = State(initialValue: initialDraft ?? SleepDraft.defaultFor(wakeDate: day))
            _editingID = State(initialValue: nil)
        case .edit(let id):
            _draft = State(initialValue: SleepDraft.defaultFor(wakeDate: .today()))
            _editingID = State(initialValue: id)
        }
    }

    private var store: JournalStore { JournalStore(context: context) }

    private var validationMessage: String? {
        do {
            _ = try draft.validated()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    DatePicker("Bedtime", selection: $draft.start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Wake time", selection: $draft.end, displayedComponents: [.date, .hourAndMinute])
                    TextField("Awake minutes (optional)", text: $draft.awakeMinutesText, prompt: Text("Blank"))
                    Picker("Quality (optional)", selection: $draft.quality) {
                        Text("Not rated").tag(Int?.none)
                        ForEach(1...5, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                    }
                    TextField("Note (optional)", text: $draft.note, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let validationMessage {
                            Label(validationMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        } else {
                            Text(calculationText)
                        }
                        Text("Wake date: \(DayKey(rawValue: draft.wakeDateKey)?.mediumLabel ?? draft.wakeDateKey)")
                            .foregroundStyle(.secondary)
                        if let saveError {
                            Text(saveError).foregroundStyle(.red)
                        }
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
                    .disabled(validationMessage != nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
        .navigationTitle(editingID == nil ? "Log sleep" : "Edit sleep")
        .onAppear(perform: loadIfEditing)
        .alert(
            "A sleep entry already exists for this wake date",
            isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
            presenting: duplicate
        ) { dup in
            Button("Edit existing entry") { openExisting(dup.id) }
            Button("Cancel", role: .cancel) {}
        } message: { dup in
            Text("Each wake date has one sleep entry. \(DayKey(rawValue: dup.key)?.longLabel ?? dup.key) already has one. Edit it instead of replacing it.")
        }
    }

    private var calculationText: String {
        let bed = DurationText.format(SleepMath.timeInBed(start: draft.start, end: draft.end))
        if let awake = try? SleepMath.parseAwakeMinutes(draft.awakeMinutesText),
           let estimate = SleepMath.estimatedSleep(start: draft.start, end: draft.end, awakeMinutes: awake) {
            return "\(bed) in bed − \(DurationText.format(TimeInterval(awake * 60))) awake = \(DurationText.format(estimate)) estimated sleep"
        }
        return "\(bed) in bed · add awake minutes to estimate sleep"
    }

    private func loadIfEditing() {
        guard !loaded else { return }
        loaded = true
        if let editingID, let entry = try? store.sleepEntry(id: editingID) {
            draft = SleepDraft(entry: entry)
        }
    }

    private func openExisting(_ id: UUID) {
        guard let entry = try? store.sleepEntry(id: id) else { return }
        editingID = id
        draft = SleepDraft(entry: entry)
    }

    private func save() {
        saveError = nil
        do {
            let editing = try editingID.flatMap { try store.sleepEntry(id: $0) }
            try store.saveSleep(draft, editing: editing)
            dismiss()
        } catch SleepSaveError.duplicateWakeDate(let id, let key) {
            duplicate = (id, key)
        } catch SleepSaveError.invalid(let error) {
            saveError = error.localizedDescription
        } catch {
            saveError = "The entry could not be saved."
        }
    }
}
