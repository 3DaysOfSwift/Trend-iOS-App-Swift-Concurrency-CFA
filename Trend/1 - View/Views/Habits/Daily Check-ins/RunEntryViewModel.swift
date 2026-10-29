// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor @Observable
final class RunEntryViewModel {
    private let feature: HabitsFeature
    var distance = 5.0
    var unit = RunningDistanceUnit.kilometres
    var errorMessage: String?
    private(set) var isSaving = false
    private(set) var didSave = false
    let habit = Habit(type: .runningDistance)

    init(feature: HabitsFeature = AppModel.shared.habitsFeature) { self.feature = feature }

    func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await feature.recordDailyValue(distance, for: habit.id, distanceUnit: unit)
            errorMessage = nil
            didSave = true
        } catch { errorMessage = error.localizedDescription }
    }
    func recordAnother() { didSave = false }
    func dismissError() { errorMessage = nil }
}
