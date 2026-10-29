// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
@testable import Trend

@MainActor
enum TestAppModelFactory {
    static let currentDate: @MainActor () -> Date = { .now }

    static func make(
        repository: any WeightRepository & CloudSyncStatusProviding = InMemoryWeightRepository(),
        purchaseClient: InMemoryPurchaseClient = InMemoryPurchaseClient(),
        unit: WeightUnit = .kilograms,
        currentDate: @escaping @MainActor () -> Date = TestAppModelFactory.currentDate
    ) -> AppModel {
        let suiteName = "TrendTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(unit.rawValue, forKey: "weightUnit")
        let dailyTrend = DailyTrendManager()
        let weightLogFeature = WeightLogFeature(repository: repository)
        let progress = ProgressTracker(currentDate: currentDate)
        let settings = UserSettingsStore(cloudSync: repository, defaults: defaults)
        let dailyTipsFeature = DailyTipsFeature(defaults: defaults, currentDate: currentDate)
        let dailyStreak = DailyStreakManager(trend: dailyTrend, currentDate: currentDate)
        let weightEntryFeature = WeightEntryFeature(
            weightLogFeature: weightLogFeature,
            progress: progress,
            settings: settings,
            dailyTrend: dailyTrend,
            dailyStreak: dailyStreak,
            currentDate: currentDate
        )
        return AppModel(
            weightLogFeature: weightLogFeature,
            weightEntryFeature: weightEntryFeature,
            progressFeature: ProgressFeature(
                progress: progress,
                weightLogFeature: weightLogFeature,
                settings: settings
            ),
            settingsFeature: SettingsFeature(
                settings: settings,
                weightLogFeature: weightLogFeature,
                progress: progress,
                dailyStreak: dailyStreak,
                backupFiles: BackupFileManager()
            ),
            habitsFeature: HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: currentDate),
            purchaseFeature: PurchaseFeature(client: purchaseClient),
            dailyTipsFeature: dailyTipsFeature,
            backupFeature: BackupFeature(storage: LocalDataStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
                files: RecoveryBackupFiles(folder: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), cloudFolder: { nil }), settings: settings, reload: {}),
            weightImportFeature: WeightImportFeature(weightLogFeature: weightLogFeature) { await weightEntryFeature.refresh() }
        )
    }
}
