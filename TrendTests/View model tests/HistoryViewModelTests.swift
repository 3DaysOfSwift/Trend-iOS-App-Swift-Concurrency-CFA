// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct HistoryViewModelTests {
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
