// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class HabitLibraryViewModel {
    private let habitsFeature: HabitsFeature

    var selection: Set<String>
    var errorMessage: String?
    var isSaving = false
    var customName = ""
    var customNames: [String] = []

    init(habitsFeature: HabitsFeature = AppModel.shared.habitsFeature) {
        self.habitsFeature = habitsFeature
        selection = Set(habitsFeature.enabledHabits.map(\.id))
    }

    var habits: [Habit] { habitsFeature.availableHabits }

    func addCustomDraft() {
        customNames.append(customName)
        customName = ""
    }

    func toggle(_ habit: Habit) {
        if selection.contains(habit.id) {
            selection.remove(habit.id)
        } else {
            selection.insert(habit.id)
        }
    }

    func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let names = customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? customNames : customNames + [customName]
            try await habitsFeature.enableSelectedHabits(selection, customNames: names)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
