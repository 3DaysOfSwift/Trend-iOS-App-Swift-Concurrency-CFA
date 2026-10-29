// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct BackupFeatureTests {
    @Test func emptyInstallationDoesNotCreateOrReplaceCloudBackups() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = root.appending(path: "Cloud")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        let existing = cloud.appending(path: "TrendBackup-existing.json")
        let sentinel = Data("previous phone backup".utf8)
        try sentinel.write(to: existing)
        let storage = LocalDataStore(directory: root.appending(path: "NewPhone"))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let manager = BackupFeature(storage: storage,
            files: RecoveryBackupFiles(folder: root.appending(path: "Backups"), cloudFolder: { cloud }),
            settings: UserSettingsStore(cloudSync: OfflineCloudStatus(), defaults: defaults), reload: {})
        await manager.backUpNow()
        #expect(try Data(contentsOf: existing) == sentinel)
        #expect(try FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil).count == 1)
        #expect(manager.status.contains("untouched"))
        await storage.close()
    }
}

private struct OfflineCloudStatus: CloudSyncStatusProviding {
    func cloudStatus() async -> CloudSyncStatus { .unavailable }
}
