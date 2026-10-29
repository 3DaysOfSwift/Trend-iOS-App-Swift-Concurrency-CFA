// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class EntryEditorViewModel {
    private let editor: WeightEntryFeature
    private let entry: WeightEntry?

    var draft: WeightEntryDraft
    var errorMessage: String?
    private(set) var isSaving = false
    private(set) var didSave = false
    @ObservationIgnored private var saveTask: Task<Bool, Never>?

    init(
        editor: WeightEntryFeature = AppModel.shared.weightEntryFeature,
        entry: WeightEntry? = nil
    ) {
        self.editor = editor
        self.entry = entry
        draft = editor.makeWeightEntryDraft(editing: entry)
    }

    var title: String { entry == nil ? "Log Weight" : "Edit Entry" }
    var unit: WeightUnit { editor.selectedWeightUnit }
    var inputStyle: WeightInputStyle { editor.weightInputStyle }
    func useKeyboard() { editor.setWeightInputStyle(.keyboard) }
    var latestPermittedEntryDate: Date { editor.latestPermittedEntryDate }
    var canSave: Bool { !draft.value.isEmpty && !isSaving }

    func save() async -> Bool { await requestSave().value }

    @discardableResult func requestSave() -> Task<Bool, Never> {
        if let saveTask { return saveTask }
        let submittedDraft = draft
        isSaving = true
        didSave = false
        errorMessage = nil
        let task = Task {
            defer { isSaving = false; saveTask = nil }
            do {
                try await editor.save(submittedDraft, editing: entry)
                didSave = true
                return true
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
        saveTask = task
        return task
    }
}
