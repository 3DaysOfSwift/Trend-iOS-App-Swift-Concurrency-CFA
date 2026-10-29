// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

enum WeightLogState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

@MainActor
@Observable
final class WeightLogManager {
    @ObservationIgnored private var operationInProgress = false
    @ObservationIgnored private var waitingOperations: [CheckedContinuation<Void, Never>] = []
    private let repository: any WeightRepository
    private(set) var state: WeightLogState = .idle
    private(set) var entries: [WeightEntry] = []
    private(set) var goalKilograms: Double?

    var latestEntry: WeightEntry? { entries.first }

    init(repository: any WeightRepository) { self.repository = repository }

    // Prepare dependent values from local data before declaring the feature ready.
    func load(prepareLoadedData: @MainActor () async -> Void = {}) async {
        await waitForPreviousOperation()
        defer { finishOperation() }
        if state != .ready { state = .loading }
        do {
            publish(try await repository.load())
            await prepareLoadedData()
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func add(_ draft: WeightEntryDraft, unit: WeightUnit) async throws {
        await waitForPreviousOperation()
        defer { finishOperation() }
        try await loadBeforeEditing()
        var candidate = store
        candidate.entries.append(WeightEntry(
            date: draft.date,
            kilograms: try draft.kilograms(using: unit),
            note: draft.note.trimmed
        ))
        try await commit(candidate)
    }

    func update(_ entry: WeightEntry, with draft: WeightEntryDraft, unit: WeightUnit) async throws {
        await waitForPreviousOperation()
        defer { finishOperation() }
        try await loadBeforeEditing()
        var candidate = store
        guard let index = candidate.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        candidate.entries[index].date = draft.date
        candidate.entries[index].kilograms = try draft.kilograms(using: unit)
        candidate.entries[index].note = draft.note.trimmed
        try await commit(candidate)
    }

    func delete(_ entry: WeightEntry) async throws {
        await waitForPreviousOperation()
        defer { finishOperation() }
        try await loadBeforeEditing()
        var candidate = store
        candidate.entries.removeAll { $0.id == entry.id }
        try await commit(candidate)
    }

    /// Stores goals in canonical kilograms. SettingsFeature converts a value
    /// entered in pounds before it reaches this persistence boundary.
    func setGoal(kilograms: Double?) async throws {
        await waitForPreviousOperation()
        defer { finishOperation() }
        try await loadBeforeEditing()
        var candidate = store
        candidate.goalKilograms = kilograms
        try await commit(candidate)
    }

    func replace(with store: WeightStore) async throws {
        await waitForPreviousOperation()
        defer { finishOperation() }
        try await loadBeforeEditing()
        try await commit(store)
    }
    func removeAll() async throws { try await replace(with: WeightStore(entries: [], goalKilograms: nil)) }

    /// Import is one serialized, additive save, never a replacement. Reload
    /// under the operation gate so a preview cannot overwrite intervening edits.
    func mergeImportedEntries(_ incoming: [WeightEntry]) async throws -> WeightImportMerge {
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        let current = try await repository.load()
        try WeightImportDocument.validate(incoming)
        try WeightImportDocument.validate(current.entries)
        let result = WeightImportMerge(incoming: incoming, existing: current.entries)
        if !result.additions.isEmpty {
            try Task.checkCancellation()
            try await commit(WeightStore(entries: current.entries + result.additions,
                                         goalKilograms: current.goalKilograms))
        } else {
            publish(current)
            state = .ready
        }
        return result
    }

    var store: WeightStore { WeightStore(entries: entries, goalKilograms: goalKilograms) }

    private func commit(_ candidate: WeightStore) async throws {
        let sorted = WeightStore(
            entries: candidate.entries.sorted { $0.date > $1.date },
            goalKilograms: candidate.goalKilograms
        )
        try await repository.save(sorted)
        publish(sorted)
        state = .ready
    }

    private func loadBeforeEditing() async throws {
        try Task.checkCancellation()
        if state != .ready { publish(try await repository.load()); state = .ready }
    }

    private func waitForPreviousOperation() async {
        if operationInProgress {
            await withCheckedContinuation { waitingOperations.append($0) }
        } else { operationInProgress = true }
    }

    private func finishOperation() {
        if waitingOperations.isEmpty { operationInProgress = false }
        else { waitingOperations.removeFirst().resume() }
    }

    private func publish(_ store: WeightStore) {
        entries = store.entries.sorted { $0.date > $1.date }
        goalKilograms = store.goalKilograms
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
