// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct HistoryViewModelTests {
    @Test(.timeLimit(.minutes(1))) func repeatedDeleteSharesWriteAndDistinctEntryStillDeletes() async throws {
        let first = WeightEntry(date: .now, kilograms: 75)
        let second = WeightEntry(date: .now, kilograms: 76)
        let repository = HistoryDeleteRepository(entries: [first, second])
        let model = HistoryViewModel(history: TestAppModelFactory.make(repository: repository).weightEntryFeature)
        await model.refresh()
        let deletion = model.requestDelete(first)
        await repository.waitForSave()
        let repeated = model.requestDelete(first)
        let other = model.requestDelete(second)
        await repository.finishSave()
        await deletion.value
        await repeated.value
        await other.value
        #expect(model.entries.isEmpty)
        #expect(await repository.writes == 2)
    }

    @Test(.timeLimit(.minutes(1))) func failedDeletionReleasesTaskForRetry() async {
        let entry = WeightEntry(date: .now, kilograms: 75)
        let repository = HistoryDeleteRepository(entries: [entry], failFirstSave: true)
        let model = HistoryViewModel(history: TestAppModelFactory.make(repository: repository).weightEntryFeature)
        await model.refresh()
        let failed = model.requestDelete(entry)
        await repository.waitForSave()
        await repository.finishSave()
        await failed.value
        #expect(model.entries == [entry])
        #expect(model.errorMessage != nil)
        model.errorMessage = nil
        await model.requestDelete(entry).value
        #expect(model.entries.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(await repository.writes == 2)
    }

    @Test func exposesLoadedEntriesStateAndUnit() async {
        let entry = WeightEntry(date: .now, kilograms: 75)
        let repository = InMemoryWeightRepository(store: .init(entries: [entry], goalKilograms: nil))
        let appModel = TestAppModelFactory.make(repository: repository, unit: .pounds)
        let viewModel = HistoryViewModel(history: appModel.weightEntryFeature)

        await viewModel.refresh()

        #expect(viewModel.state == .ready)
        #expect(viewModel.entries == [entry])
        #expect(viewModel.unit == .pounds)
    }
    @Test func deleteRemovesEntryAndRefreshesProgress() async throws {
        let entry = WeightEntry(date: .now, kilograms: 75)
        let repository = InMemoryWeightRepository(store: .init(entries: [entry], goalKilograms: nil))
        let appModel = TestAppModelFactory.make(repository: repository)
        await appModel.weightEntryFeature.refresh()
        let viewModel = HistoryViewModel(history: appModel.weightEntryFeature)

        await viewModel.delete(entry)

        #expect(viewModel.entries.isEmpty)
        #expect(appModel.progressFeature.progressSnapshot == .empty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func deleteFailureIsPresentedAndEntryRemains() async {
        let entry = WeightEntry(date: .now, kilograms: 75)
        let repository = InMemoryWeightRepository(
            store: .init(entries: [entry], goalKilograms: nil),
            saveError: .saveFailed
        )
        let appModel = TestAppModelFactory.make(repository: repository)
        await appModel.weightEntryFeature.refresh()
        let viewModel = HistoryViewModel(history: appModel.weightEntryFeature)

        await viewModel.delete(entry)

        #expect(viewModel.entries == [entry])
        #expect(viewModel.errorMessage == "The test repository could not save.")
    }

    @Test func refreshExposesLoadFailure() async {
        let repository = InMemoryWeightRepository(loadError: .loadFailed)
        let viewModel = HistoryViewModel(history: TestAppModelFactory.make(repository: repository).weightEntryFeature)

        await viewModel.refresh()

        #expect(viewModel.state == .failed("The test repository could not load."))
    }
}

private actor HistoryDeleteRepository: WeightRepository, CloudSyncStatusProviding {
    private var store: WeightStore
    private var release: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var writes = 0
    private let failFirstSave: Bool
    private enum SaveFailure: Error { case unavailable }
    init(entries: [WeightEntry], failFirstSave: Bool = false) {
        store = WeightStore(entries: entries, goalKilograms: nil)
        self.failFirstSave = failFirstSave
    }
    func cloudStatus() -> CloudSyncStatus { .unavailable }
    func load() -> WeightStore { store }
    func save(_ candidate: WeightStore) async throws {
        writes += 1
        if writes == 1 {
            await withCheckedContinuation { continuation in
                release = continuation
                started?.resume()
                started = nil
            }
        }
        if writes == 1 && failFirstSave { throw SaveFailure.unavailable }
        store = candidate
    }
    func waitForSave() async {
        if release != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finishSave() { release?.resume(); release = nil }
}
