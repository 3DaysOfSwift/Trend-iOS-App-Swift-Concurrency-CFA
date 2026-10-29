// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct TodayViewModelTests {
    @Test func habitsRequireWeightRecordedForTodayAndSurviveViewRecreation() async {
        let now = Date()
        let appModel = TestAppModelFactory.make(currentDate: { now })
        await appModel.weightEntryFeature.refresh()
        let viewModel = TodayViewModel(weightEntryFeature: appModel.weightEntryFeature, dailyTipsFeature: appModel.dailyTipsFeature)
        #expect(!viewModel.showsHabits)

        viewModel.draft = WeightEntryDraft(
            date: Calendar.current.date(byAdding: .day, value: -1, to: now)!,
            value: "72.5", note: ""
        )
        #expect(await viewModel.save())
        #expect(!viewModel.showsHabits)

        viewModel.draft = WeightEntryDraft(date: now, value: "72.4", note: "")
        #expect(await viewModel.save())
        #expect(viewModel.showsHabits)
        #expect(TodayViewModel(weightEntryFeature: appModel.weightEntryFeature, dailyTipsFeature: appModel.dailyTipsFeature).showsHabits)
    }

    @Test func newDraftAndDateBoundaryComeFromAppModelClock() {
        let now = Date(timeIntervalSince1970: 1_000)
        let app = TestAppModelFactory.make(currentDate: { now })
        let viewModel = TodayViewModel(weightEntryFeature: app.weightEntryFeature, dailyTipsFeature: app.dailyTipsFeature)

        #expect(viewModel.draft.date == now)
        #expect(viewModel.latestPermittedEntryDate == now)
    }

    @Test func emptyStateHasNoLatestEntryOrChange() {
        let app = TestAppModelFactory.make()
        let viewModel = TodayViewModel(weightEntryFeature: app.weightEntryFeature, dailyTipsFeature: app.dailyTipsFeature)

        #expect(viewModel.latestEntry == nil)
        #expect(viewModel.changeKilograms == nil)
        #expect(viewModel.unit == .kilograms)
    }

    @Test func exposesLatestEntryTrendAndUnit() async {
        let now = Date()
        let older = WeightEntry(date: now.addingTimeInterval(-86_400), kilograms: 82)
        let latest = WeightEntry(date: now, kilograms: 80)
        let repository = InMemoryWeightRepository(store: .init(entries: [older, latest], goalKilograms: nil))
        let appModel = TestAppModelFactory.make(repository: repository, unit: .pounds)
        await appModel.weightEntryFeature.refresh()
        let viewModel = TodayViewModel(weightEntryFeature: appModel.weightEntryFeature, dailyTipsFeature: appModel.dailyTipsFeature)

        #expect(viewModel.latestEntry == latest)
        #expect(viewModel.changeKilograms == -2)
        #expect(viewModel.unit == .pounds)
    }

    @Test func savingWeightPublishesEntryAndKeepsSubmittedDraft() async {
        let repository = InMemoryWeightRepository()
        let appModel = TestAppModelFactory.make(repository: repository)
        let viewModel = TodayViewModel(weightEntryFeature: appModel.weightEntryFeature, dailyTipsFeature: appModel.dailyTipsFeature)
        viewModel.draft = WeightEntryDraft(
            date: Date(timeIntervalSince1970: 456),
            value: "72.5",
            note: " Morning "
        )

        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(appModel.weightEntryFeature.latestWeightEntry?.kilograms == 72.5)
        #expect(appModel.weightEntryFeature.latestWeightEntry?.note == "Morning")
        #expect(viewModel.draft.value == "72.5")
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isSaving)
        #expect(viewModel.submittedResult != nil)
    }

    @Test func successfulCheckInUsesTheAppModelsTipDeckButFailedSaveDoesNotConsumeIt() async {
        let app = TestAppModelFactory.make()
        let viewModel = TodayViewModel(
            weightEntryFeature: app.weightEntryFeature,
            dailyTipsFeature: app.dailyTipsFeature
        )
        viewModel.draft.value = "72.5"
        #expect(await viewModel.save())
        #expect(app.dailyTipsFeature.remainingCount == 99)
        #expect(app.dailyTipsFeature.remainingPepTalkCount == 99)
        let firstResult = viewModel.submittedResult
        viewModel.draft.value = "invalid"
        #expect(!(await viewModel.save()))
        #expect(app.dailyTipsFeature.remainingCount == 99)
        #expect(viewModel.submittedResult == firstResult)
        viewModel.draft.value = "72.4"
        #expect(await viewModel.save())
        #expect(app.dailyTipsFeature.remainingCount == 98)
        #expect(viewModel.submittedResult?.tip != firstResult?.tip)
    }

    @Test func beginningAnotherCheckInCreatesFreshDraft() async {
        let app = TestAppModelFactory.make()
        let viewModel = TodayViewModel(weightEntryFeature: app.weightEntryFeature, dailyTipsFeature: app.dailyTipsFeature)
        viewModel.draft.value = "72.5"

        #expect(await viewModel.save())
        viewModel.beginAnotherCheckIn()

        #expect(viewModel.draft.value == "72.5")
        #expect(viewModel.submittedResult == nil)
    }

    @Test func invalidWeightRemainsInDraftAndShowsMessage() async {
        let app = TestAppModelFactory.make()
        let viewModel = TodayViewModel(weightEntryFeature: app.weightEntryFeature, dailyTipsFeature: app.dailyTipsFeature)
        viewModel.draft.value = "invalid"

        let didSave = await viewModel.save()

        #expect(!didSave)
        #expect(viewModel.draft.value == "invalid")
        #expect(viewModel.errorMessage == "Enter a weight between 20 and 500 kg.")
        #expect(!viewModel.isSaving)
    }

    @Test func loadSeedsLatestWeightWithoutCopyingOldDateOrNote() async {
        let now = Date(timeIntervalSince1970: 100_000)
        let previous = WeightEntry(date: now.addingTimeInterval(-86_400), kilograms: 69.7, note: "Yesterday")
        let app = TestAppModelFactory.make(repository: InMemoryWeightRepository(
            store: .init(entries: [previous], goalKilograms: nil)), currentDate: { now })
        let viewModel = TodayViewModel(weightEntryFeature: app.weightEntryFeature, dailyTipsFeature: app.dailyTipsFeature)
        await viewModel.refresh()
        viewModel.prepareWeightInput()
        #expect(viewModel.draft.value == "69.7")
        #expect(viewModel.draft.date == now)
        #expect(viewModel.draft.note.isEmpty)
        viewModel.draft.value = "69.6"
        viewModel.prepareWeightInput()
        #expect(viewModel.draft.value == "69.6")
        #expect(app.weightEntryFeature.entries.count == 1)
    }

    @Test func changingUnitsConvertsDraftRatherThanRelabelingItsNumber() async {
        let app = TestAppModelFactory.make()
        let viewModel = TodayViewModel(weightEntryFeature: app.weightEntryFeature, dailyTipsFeature: app.dailyTipsFeature)
        viewModel.draft.value = "45.359237"
        app.settingsFeature.setWeightUnit(.pounds)
        viewModel.updateInputUnit()
        #expect(viewModel.draft.value == "100.0")
    }

    @Test func persistenceFailureKeepsEnteredWeightForRetry() async {
        let repository = InMemoryWeightRepository(saveError: .saveFailed)
        let app = TestAppModelFactory.make(repository: repository)
        let viewModel = TodayViewModel(weightEntryFeature: app.weightEntryFeature, dailyTipsFeature: app.dailyTipsFeature)
        viewModel.draft.value = "75"

        let didSave = await viewModel.save()

        #expect(!didSave)
        #expect(viewModel.draft.value == "75")
        #expect(viewModel.errorMessage == "The test repository could not save.")
    }
}
