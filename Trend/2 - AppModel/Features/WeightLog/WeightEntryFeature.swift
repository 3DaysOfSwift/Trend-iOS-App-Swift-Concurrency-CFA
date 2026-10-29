// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

/// Owns every workflow concerned with creating, editing, listing, and deleting
/// weight entries. Multiple interfaces can reuse these rules without copying them.
@MainActor
@Observable
final class WeightEntryFeature {
    enum EntryDateError: LocalizedError, Equatable {
        case futureDate

        var errorDescription: String? {
            "A weight entry cannot be dated in the future."
        }
    }

    private let weightLog: WeightLogManager
    private let progress: ProgressTracker
    private let settings: UserSettingsStore
    private let dailyTrend: DailyTrendManager
    private let dailyStreak: DailyStreakManager

    /// A function, rather than a stored Date, keeps production time moving while
    /// allowing tests to supply a fixed date and verify time-based rules reliably.
    private let currentDate: @MainActor () -> Date

    init(
        weightLog: WeightLogManager,
        progress: ProgressTracker,
        settings: UserSettingsStore,
        dailyTrend: DailyTrendManager,
        dailyStreak: DailyStreakManager,
        currentDate: @escaping @MainActor () -> Date
    ) {
        self.weightLog = weightLog
        self.progress = progress
        self.settings = settings
        self.dailyTrend = dailyTrend
        self.dailyStreak = dailyStreak
        self.currentDate = currentDate
    }

    var latestWeightEntry: WeightEntry? { weightLog.latestEntry }
    var hasRecordedWeightToday: Bool {
        let now = currentDate()
        return weightLog.entries.contains { Calendar.current.isDate($0.date, inSameDayAs: now) }
    }
    var latestWeightChangeKilograms: Double? { progress.snapshot.changeKilograms }
    var progressSnapshot: WeightHistoryData { progress.snapshot }
    var goalWeightKilograms: Double? { weightLog.goalKilograms }
    var dailyStreakSnapshot: DailyStreakSnapshot { dailyStreak.snapshot }
    var selectedWeightUnit: WeightUnit { settings.unit }
    var weightInputStyle: WeightInputStyle { settings.weightInputStyle }
    func setWeightInputStyle(_ style: WeightInputStyle) { settings.weightInputStyle = style }

    /// A new check-in suggests the latest measurement, never an assumed loss.
    /// Its date is today and its note is empty, not copied from the old entry.
    func makeDailyWeightDraft() -> WeightEntryDraft {
        var draft = makeWeightEntryDraft(editing: nil)
        if let latest = weightLog.latestEntry {
            draft.value = settings.unit.value(fromKilograms: latest.kilograms)
                .formatted(.number.grouping(.never).precision(.fractionLength(1)))
        }
        return draft
    }

    func convertWeightInput(_ text: String, from unit: WeightUnit) -> String {
        guard let kilograms = try? unit.kilograms(from: text) else { return "" }
        return settings.unit.value(fromKilograms: kilograms)
            .formatted(.number.grouping(.never).precision(.fractionLength(1)))
    }
    var latestPermittedEntryDate: Date { currentDate() }
    var weightLogState: WeightLogState { weightLog.state }
    var entries: [WeightEntry] { weightLog.entries }

    func makeWeightEntryDraft(editing entry: WeightEntry?) -> WeightEntryDraft {
        let unit = settings.unit
        return WeightEntryDraft(
            date: entry?.date ?? currentDate(),
            value: entry.map {
                unit.value(fromKilograms: $0.kilograms)
                    .formatted(.number.grouping(.never).precision(.fractionLength(1)))
            } ?? "",
            note: entry?.note ?? ""
        )
    }

    func save(_ draft: WeightEntryDraft, editing entry: WeightEntry?) async throws {
        try validateEntryDate(draft.date)
        if let entry {
            try await weightLog.update(entry, with: draft, unit: settings.unit)
        } else {
            try await weightLog.add(draft, unit: settings.unit)
        }
        await refreshDerivedFeatures()
    }

    func checkIn(_ draft: WeightEntryDraft) async throws -> DailyTrendAssessment {
        try validateEntryDate(draft.date)
        let existingIDs = Set(weightLog.entries.map(\.id))
        try await weightLog.add(draft, unit: settings.unit)
        guard let newEntry = weightLog.entries.first(where: { !existingIDs.contains($0.id) }) else {
            preconditionFailure("A successful check-in must create a weight entry.")
        }

        await refreshDerivedFeatures()
        let assessment = await dailyTrend.assess(
            entries: weightLog.entries,
            newestEntryID: newEntry.id
        )
        return assessment
    }

    func delete(_ entry: WeightEntry) async throws {
        try await weightLog.delete(entry)
        await refreshDerivedFeatures()
    }

    func refresh() async {
        await weightLog.load {
            await self.refreshDerivedFeatures()
        }
    }

    private func refreshDerivedFeatures() async {
        let entries = weightLog.entries
        let goalKilograms = weightLog.goalKilograms
        let progressTask = Task { @MainActor [progress] in
            await progress.refresh(entries: entries, goalKilograms: goalKilograms)
        }
        let streakTask = Task { @MainActor [dailyStreak] in
            await dailyStreak.refresh(entries: entries)
        }

        await progressTask.value
        await streakTask.value
    }

    private func validateEntryDate(_ date: Date) throws {
        guard date <= currentDate() else { throw EntryDateError.futureDate }
    }
}
