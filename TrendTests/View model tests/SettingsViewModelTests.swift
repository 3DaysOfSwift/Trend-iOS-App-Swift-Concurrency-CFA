// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct SettingsViewModelTests {
    @Test func initialStateReflectsStoredGoalAndUnit() async {
        let repository = InMemoryWeightRepository(store: .init(entries: [], goalKilograms: 70))
        let appModel = TestAppModelFactory.make(repository: repository)
        await appModel.weightEntryFeature.refresh()
        await appModel.settingsFeature.refreshCloudStatus()

        let viewModel = SettingsViewModel(settings: appModel.settingsFeature)

        #expect(viewModel.unit == .kilograms)
        #expect(viewModel.goalText == "70.0")
        #expect(viewModel.cloudStatus == .unavailable)
        #expect(!viewModel.isExporting)
        #expect(!viewModel.isImporting)
        #expect(!viewModel.confirmDelete)
    }

    @Test func changingUnitConvertsGoalText() async {
        let repository = InMemoryWeightRepository(store: .init(entries: [], goalKilograms: 45.359237))
        let appModel = TestAppModelFactory.make(repository: repository)
        await appModel.weightEntryFeature.refresh()
        await appModel.settingsFeature.refreshCloudStatus()
        let viewModel = SettingsViewModel(settings: appModel.settingsFeature)

        viewModel.unit = .pounds

        #expect(viewModel.unit == .pounds)
        #expect(viewModel.goalText == "100.0")
    }

    @Test func refreshCloudStatusPublishesProviderValue() async {
        let repository = InMemoryWeightRepository(cloudStatus: .available)
        let viewModel = SettingsViewModel(settings: TestAppModelFactory.make(repository: repository).settingsFeature)

        await viewModel.refreshCloudStatus()

        #expect(viewModel.cloudStatus == .available)
    }

    @Test func validGoalIsSavedInCanonicalKilograms() async {
        let repository = InMemoryWeightRepository()
        let appModel = TestAppModelFactory.make(repository: repository, unit: .pounds)
        let viewModel = SettingsViewModel(settings: appModel.settingsFeature)
        viewModel.goalText = "154.3"

        await viewModel.saveGoal()

        #expect(abs((appModel.settingsFeature.goalWeightKilograms ?? 0) - 69.989) < 0.01)
        #expect(viewModel.message == nil)
    }

    @Test func invalidGoalShowsValidationMessage() async {
        let viewModel = SettingsViewModel(settings: TestAppModelFactory.make().settingsFeature)
        viewModel.goalText = "10"

        await viewModel.saveGoal()

        #expect(viewModel.message == "Enter a weight between 20 and 500 kg.")
    }

    @Test func goalSaveAvailabilityUsesTheSameValidationAsSaving() {
        let viewModel = SettingsViewModel(settings: TestAppModelFactory.make().settingsFeature)

        viewModel.goalText = "10"
        #expect(!viewModel.canSaveGoal)

        viewModel.goalText = "70"
        #expect(viewModel.canSaveGoal)
    }

    @Test func exportProducesJSONDocumentAndOpensExporter() async {
        let repository = InMemoryWeightRepository(store: .init(entries: [], goalKilograms: 70))
        let appModel = TestAppModelFactory.make(repository: repository)
        await appModel.weightEntryFeature.refresh()
        await appModel.settingsFeature.refreshCloudStatus()
        let viewModel = SettingsViewModel(settings: appModel.settingsFeature)

        await viewModel.prepareExport()

        #expect(viewModel.exportDocument != nil)
        #expect(viewModel.isExporting)
        #expect(viewModel.message == nil)
    }

    @Test func importPickerFailureIsPresented() async {
        let viewModel = SettingsViewModel(settings: TestAppModelFactory.make().settingsFeature)
        let error = CocoaError(.fileReadCorruptFile)

        viewModel.selectImportFile(.failure(error))

        #expect(viewModel.message == error.localizedDescription)
    }

    @Test func deleteAllClearsEntriesGoalAndText() async {
        let entry = WeightEntry(date: .now, kilograms: 80)
        let repository = InMemoryWeightRepository(store: .init(entries: [entry], goalKilograms: 70))
        let appModel = TestAppModelFactory.make(repository: repository)
        await appModel.weightEntryFeature.refresh()
        await appModel.settingsFeature.refreshCloudStatus()
        let viewModel = SettingsViewModel(settings: appModel.settingsFeature)

        await viewModel.deleteAllData()

        #expect(appModel.weightEntryFeature.entries.isEmpty)
        #expect(appModel.settingsFeature.goalWeightKilograms == nil)
        #expect(viewModel.goalText.isEmpty)
    }

    @Test func deleteFailurePreservesDataAndShowsMessage() async {
        let entry = WeightEntry(date: .now, kilograms: 80)
        let repository = InMemoryWeightRepository(
            store: .init(entries: [entry], goalKilograms: 70),
            saveError: .saveFailed
        )
        let appModel = TestAppModelFactory.make(repository: repository)
        await appModel.weightEntryFeature.refresh()
        await appModel.settingsFeature.refreshCloudStatus()
        let viewModel = SettingsViewModel(settings: appModel.settingsFeature)

        await viewModel.deleteAllData()

        #expect(appModel.weightEntryFeature.entries == [entry])
        #expect(viewModel.goalText == "70.0")
        #expect(viewModel.message == "The test repository could not save.")
    }
}
