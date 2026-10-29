// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct EntryEditorViewModelTests {
    @Test(.timeLimit(.minutes(1))) func repeatedSaveSharesOneWrite() async throws {
        let repository = EditorSaveRepository()
        let model = EntryEditorViewModel(editor: TestAppModelFactory.make(repository: repository).weightEntryFeature)
        model.draft.value = "75"
        let first = Task { await model.save() }
        await repository.waitForSave()
        var second: Task<Bool, Never>?
        await withCheckedContinuation { started in
            second = Task {
                started.resume()
                return await model.save()
            }
        }
        #expect(model.isSaving)
        await repository.finishSave()
        #expect(await first.value)
        let repeated = try #require(second)
        #expect(await repeated.value)
        #expect(await repository.load().entries.count == 1)
        #expect(await repository.writes == 1)
        #expect(!model.isSaving)
    }

    @Test func newDraftAndDateBoundaryComeFromAppModelClock() {
        let now = Date(timeIntervalSince1970: 1_000)
        let viewModel = EntryEditorViewModel(
            editor: TestAppModelFactory.make(currentDate: { now }).weightEntryFeature
        )

        #expect(viewModel.draft.date == now)
        #expect(viewModel.latestPermittedEntryDate == now)
    }

    @Test func newEntryStartsEmptyAndUsesCurrentUnit() {
        let appModel = TestAppModelFactory.make(unit: .pounds)
        let viewModel = EntryEditorViewModel(editor: appModel.weightEntryFeature)

        #expect(viewModel.title == "Log Weight")
        #expect(viewModel.draft.value.isEmpty)
        #expect(viewModel.unit == .pounds)
        #expect(!viewModel.canSave)
        #expect(!viewModel.isSaving)
    }

    @Test func existingEntryPopulatesEditableDraft() {
        let entry = WeightEntry(date: Date(timeIntervalSince1970: 123), kilograms: 70, note: "Morning")
        let appModel = TestAppModelFactory.make()
        let viewModel = EntryEditorViewModel(editor: appModel.weightEntryFeature, entry: entry)

        #expect(viewModel.title == "Edit Entry")
        #expect(viewModel.draft.date == entry.date)
        #expect(viewModel.draft.value == "70.0")
        #expect(viewModel.draft.note == "Morning")
    }

    @Test func savingNewEntryPersistsAndDismisses() async {
        let repository = InMemoryWeightRepository()
        let appModel = TestAppModelFactory.make(repository: repository)
        let viewModel = EntryEditorViewModel(editor: appModel.weightEntryFeature)
        viewModel.draft = WeightEntryDraft(date: Date(timeIntervalSince1970: 456), value: "72.5", note: " Evening ")

        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isSaving)
        #expect(appModel.weightEntryFeature.latestWeightEntry?.kilograms == 72.5)
        #expect(appModel.weightEntryFeature.latestWeightEntry?.note == "Evening")
    }

    @Test func savingExistingEntryUpdatesIt() async {
        let entry = WeightEntry(date: .now, kilograms: 80)
        let repository = InMemoryWeightRepository(store: .init(entries: [entry], goalKilograms: nil))
        let appModel = TestAppModelFactory.make(repository: repository)
        await appModel.weightEntryFeature.refresh()
        let viewModel = EntryEditorViewModel(editor: appModel.weightEntryFeature, entry: entry)
        viewModel.draft.value = "79"

        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(appModel.weightEntryFeature.entries.count == 1)
        #expect(appModel.weightEntryFeature.latestWeightEntry?.kilograms == 79)
    }

    @Test func invalidWeightShowsValidationAndDoesNotDismiss() async {
        let appModel = TestAppModelFactory.make()
        let viewModel = EntryEditorViewModel(editor: appModel.weightEntryFeature)
        viewModel.draft.value = "not a number"

        let didSave = await viewModel.save()

        #expect(!didSave)
        #expect(viewModel.errorMessage == "Enter a weight between 20 and 500 kg.")
        #expect(!viewModel.isSaving)
    }

    @Test func repositoryFailureIsPresentedAndDoesNotDismiss() async {
        let repository = InMemoryWeightRepository(saveError: .saveFailed)
        let appModel = TestAppModelFactory.make(repository: repository)
        let viewModel = EntryEditorViewModel(editor: appModel.weightEntryFeature)
        viewModel.draft.value = "75"

        let didSave = await viewModel.save()

        #expect(!didSave)
        #expect(viewModel.errorMessage == "The test repository could not save.")
    }
}

private actor EditorSaveRepository: WeightRepository, CloudSyncStatusProviding {
    func cloudStatus() -> CloudSyncStatus { .unavailable }
    private var store = WeightStore(entries: [], goalKilograms: nil)
    private var release: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var writes = 0
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
        store = candidate
    }
    func waitForSave() async {
        if release != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finishSave() { release?.resume(); release = nil }
}
