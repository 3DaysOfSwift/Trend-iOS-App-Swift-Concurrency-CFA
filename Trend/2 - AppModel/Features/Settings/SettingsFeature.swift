// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

/// Owns settings, goal, backup, and whole-account data workflows.
@MainActor
@Observable
final class SettingsFeature {
    private let settings: UserSettingsStore
    private let weightLogFeature: WeightLogFeature
    private let progress: ProgressTracker
    private let dailyStreak: DailyStreakManager
    private let backupFiles: BackupFileManager

    init(
        settings: UserSettingsStore,
        weightLogFeature: WeightLogFeature,
        progress: ProgressTracker,
        dailyStreak: DailyStreakManager,
        backupFiles: BackupFileManager
    ) {
        self.settings = settings
        self.weightLogFeature = weightLogFeature
        self.progress = progress
        self.dailyStreak = dailyStreak
        self.backupFiles = backupFiles
    }

    var selectedWeightUnit: WeightUnit { settings.unit }
    var weightInputStyle: WeightInputStyle { settings.weightInputStyle }
    func setWeightInputStyle(_ style: WeightInputStyle) { settings.weightInputStyle = style }
    var cloudSyncStatus: CloudSyncStatus { settings.cloudStatus }
    var goalWeightKilograms: Double? { weightLogFeature.goalKilograms }

    func setWeightUnit(_ unit: WeightUnit) {
        settings.unit = unit
    }

    func refreshCloudStatus() async {
        await settings.refreshCloudStatus()
    }

    func canSetGoal(from text: String) -> Bool {
        (try? settings.unit.kilograms(from: text)) != nil
    }

    func setGoal(from text: String) async throws {
        try await weightLogFeature.setGoal(kilograms: settings.unit.kilograms(from: text))
        await progress.refresh(
            entries: weightLogFeature.entries,
            goalKilograms: weightLogFeature.goalKilograms
        )
    }

    func exportData() async throws -> Data {
        try await backupFiles.encode(weightLogFeature.store)
    }

    func deleteAllData() async throws {
        try await weightLogFeature.removeAll()
        await progress.refresh(entries: [])
        await dailyStreak.refresh(entries: [])
    }

}
