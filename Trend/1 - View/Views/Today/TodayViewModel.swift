// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {
    private let weightEntryFeature: WeightEntryFeature
    private let dailyTipsFeature: DailyTipsFeature
    private var hasPreparedInput = false
    private var inputUnit: WeightUnit

    var draft: WeightEntryDraft
    var errorMessage: String?
    private(set) var isSaving = false
    private(set) var submittedResult: DailyCheckInResult?

    init(
        weightEntryFeature: WeightEntryFeature = AppModel.shared.weightEntryFeature,
        dailyTipsFeature: DailyTipsFeature = AppModel.shared.dailyTipsFeature
    ) {
        self.dailyTipsFeature = dailyTipsFeature
        self.weightEntryFeature = weightEntryFeature
        draft = weightEntryFeature.makeDailyWeightDraft()
        inputUnit = weightEntryFeature.selectedWeightUnit
        hasPreparedInput = weightEntryFeature.weightLogState == .ready
    }

    var latestEntry: WeightEntry? { weightEntryFeature.latestWeightEntry }
    var showsHabits: Bool { weightEntryFeature.weightLogState == .ready && weightEntryFeature.hasRecordedWeightToday }
    var loadState: WeightLogState { weightEntryFeature.weightLogState }
    var changeKilograms: Double? { weightEntryFeature.latestWeightChangeKilograms }
    var progressSnapshot: WeightHistoryData { weightEntryFeature.progressSnapshot }
    var goalKilograms: Double? { weightEntryFeature.goalWeightKilograms }
    var streakSnapshot: DailyStreakSnapshot { weightEntryFeature.dailyStreakSnapshot }
    var unit: WeightUnit { weightEntryFeature.selectedWeightUnit }
    var inputStyle: WeightInputStyle { weightEntryFeature.weightInputStyle }
    func useKeyboard() { weightEntryFeature.setWeightInputStyle(.keyboard) }

    func prepareWeightInput() {
        guard loadState == .ready, !hasPreparedInput else { return }
        if draft.value.isEmpty {
            draft.value = weightEntryFeature.makeDailyWeightDraft().value
        }
        hasPreparedInput = true
    }

    func updateInputUnit() {
        guard inputUnit != unit else { return }
        draft.value = weightEntryFeature.convertWeightInput(draft.value, from: inputUnit)
        inputUnit = unit
    }
    var latestPermittedEntryDate: Date { weightEntryFeature.latestPermittedEntryDate }
    var canSave: Bool { loadState == .ready && !draft.value.isEmpty && !isSaving }

    func refresh() async {
        await weightEntryFeature.refresh()
    }

    func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        do {
            let assessment = try await weightEntryFeature.checkIn(draft)
            submittedResult = DailyCheckInResult(
                assessment: assessment,
                tip: dailyTipsFeature.nextTip(),
                pepTalk: dailyTipsFeature.nextPepTalk(),
                poisonPoint: dailyTipsFeature.nextPoisonPoint(),
                evolutionPoint: dailyTipsFeature.nextEvolutionPoint(),
                fastingPoint: dailyTipsFeature.currentFastingSuggestion,
                whatNext: dailyTipsFeature.whatNext()
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func beginAnotherCheckIn() {
        draft = weightEntryFeature.makeDailyWeightDraft()
        inputUnit = unit
        hasPreparedInput = loadState == .ready
        submittedResult = nil
        errorMessage = nil
    }
}
