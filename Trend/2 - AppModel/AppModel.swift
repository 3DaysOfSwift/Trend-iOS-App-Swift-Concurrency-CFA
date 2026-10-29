// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation

/// The composition root for the application.
///
/// AppModel constructs and exposes Features. Application behavior lives
/// in those features rather than accumulating in this assembly type.
@MainActor
final class AppModel {
    /// The single production dependency graph used by the running app.
    static let shared = AppModel.live()

    let weightEntryFeature: WeightEntryFeature
    let progressFeature: ProgressFeature
    let settingsFeature: SettingsFeature
    let habitsFeature: HabitsFeature
    let purchaseFeature: PurchaseFeature
    let backupFeature: BackupFeature
    let weightImportFeature: WeightImportFeature
    let dailyTipsFeature: DailyTipsFeature
    private var hasLaunched = false

    init(
        weightEntryFeature: WeightEntryFeature,
        progressFeature: ProgressFeature,
        settingsFeature: SettingsFeature,
        habitsFeature: HabitsFeature,
        purchaseFeature: PurchaseFeature,
        dailyTipsFeature: DailyTipsFeature,
        backupFeature: BackupFeature,
        weightImportFeature: WeightImportFeature
    ) {
        self.weightEntryFeature = weightEntryFeature
        self.progressFeature = progressFeature
        self.settingsFeature = settingsFeature
        self.habitsFeature = habitsFeature
        self.purchaseFeature = purchaseFeature
        self.dailyTipsFeature = dailyTipsFeature
        self.backupFeature = backupFeature
        self.weightImportFeature = weightImportFeature
    }

    /// Produces the live, non-test AppModel and assembles all production
    /// dependencies in one visible place.
    static func live() -> AppModel {
        // A function, rather than a stored Date, keeps production time moving
        // while allowing tests to provide a fixed clock.
        let currentDate: @MainActor () -> Date = { .now }

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Trend", directoryHint: .isDirectory)
        let storage = LocalDataStore(directory: directory,
            cloudContainerIdentifier: "iCloud.com.3DaysOfSwiftConcurrency.Trend.SwiftData")
        let repository = LocalWeightRepository(storage: storage)
        let weightLog = WeightLogManager(repository: repository)
        let progress = ProgressTracker(currentDate: currentDate)
        let settings = UserSettingsStore(cloudSync: ICloudDriveAvailability())
        let dailyTrend = DailyTrendManager()
        let dailyTipsFeature = DailyTipsFeature(currentDate: currentDate)
        let dailyStreak = DailyStreakManager(trend: dailyTrend, currentDate: currentDate)
        let backupFiles = BackupFileManager()
        let habitDataStore = LocalHabitRepository(storage: storage)
        let habitsFeature = HabitsFeature(
            storage: habitDataStore,
            currentDate: currentDate
        )
        let purchaseFeature = PurchaseFeature(client: StoreKitPurchaseClient())

        let weightEntryFeature = WeightEntryFeature(
            weightLog: weightLog,
            progress: progress,
            settings: settings,
            dailyTrend: dailyTrend,
            dailyStreak: dailyStreak,
            currentDate: currentDate
        )
        let progressFeature = ProgressFeature(
            progress: progress,
            weightLog: weightLog,
            settings: settings
        )
        let settingsFeature = SettingsFeature(
            settings: settings,
            weightLog: weightLog,
            progress: progress,
            dailyStreak: dailyStreak,
            backupFiles: backupFiles
        )
        let backupFeature = BackupFeature(storage: storage,
            files: RecoveryBackupFiles(folder: directory.appending(path: "Backups")), settings: settings) {
                await weightEntryFeature.refresh()
                await habitsFeature.reload()
            }
        return AppModel(
            weightEntryFeature: weightEntryFeature,
            progressFeature: progressFeature,
            settingsFeature: settingsFeature,
            habitsFeature: habitsFeature,
            purchaseFeature: purchaseFeature,
            dailyTipsFeature: dailyTipsFeature,
            backupFeature: backupFeature,
            weightImportFeature: WeightImportFeature(weightLog: weightLog) { await weightEntryFeature.refresh() }
        )
    }

    /// Registers observation immediately and starts independent loads once.
    func applicationDidFinishLaunching() {
        guard !hasLaunched else { return }
        hasLaunched = true

        purchaseFeature.observeTransactionUpdates()
        dailyTipsFeature.refresh()
        backupFeature.observeLocalChanges()
        backupFeature.observeCloudChanges()
        Task { await backupFeature.triggerDataBackupIfNeeded() }
        
        Task { await purchaseFeature.refreshStoreState() }
        Task { await settingsFeature.refreshCloudStatus() }
        Task { await weightEntryFeature.refresh() }
        Task { await habitsFeature.load() }
    }
    
    func applicationDidBecomeActive() {
        Task {
            await weightEntryFeature.refresh()
            await habitsFeature.reload()
            await backupFeature.triggerDataBackupIfNeeded()
        }
    }

    func applicationSignificantTimeChange() {
        Task { await habitsFeature.updateCurrentDay() }
    }
}
