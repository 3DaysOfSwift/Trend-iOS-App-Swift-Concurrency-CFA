// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class HistoryViewModel {
    private let history: WeightEntryFeature
    var errorMessage: String?
    @ObservationIgnored private var deletionTasks: [UUID: Task<Void, Never>] = [:]

    init(history: WeightEntryFeature = AppModel.shared.weightEntryFeature) {
        self.history = history
    }

    var state: WeightLogState { history.weightLogState }
    var entries: [WeightEntry] { history.entries }
    var unit: WeightUnit { history.selectedWeightUnit }

    func delete(_ entry: WeightEntry) async {
        await requestDelete(entry).value
    }

    @discardableResult func requestDelete(_ entry: WeightEntry) -> Task<Void, Never> {
        if let existing = deletionTasks[entry.id] { return existing }
        let task = Task {
            defer { deletionTasks[entry.id] = nil }
            do { try await history.delete(entry) }
            catch { errorMessage = error.localizedDescription }
        }
        deletionTasks[entry.id] = task
        return task
    }

    func refresh() async { await history.refresh() }
}
