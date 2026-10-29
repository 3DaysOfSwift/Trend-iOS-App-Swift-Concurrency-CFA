// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct BackupFeatureTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func restoreProtectsRecordsUntilReloadFinishes(cancelCaller: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = LocalDataStore(directory: root)
        let original = WeightEntry(date: .now, kilograms: 70)
        try await storage.saveWeight(WeightStore(entries: [original], goalKilograms: nil))
        let snapshot = try await storage.snapshot()
        let current = WeightEntry(date: .now, kilograms: 69)
        try await storage.saveWeight(WeightStore(entries: [current], goalKilograms: nil))
        let enteredReload = AsyncStream<Void>.makeStream()
        let releaseReload = AsyncStream<Void>.makeStream()
        defer {
            enteredReload.continuation.finish()
            releaseReload.continuation.finish()
        }
        let feature = BackupFeature(storage: storage,
            files: RecoveryBackupFiles(folder: root.appending(path: "Backups"), cloudFolder: { nil }),
            settings: UserSettingsStore(cloudSync: OfflineCloudStatus(), defaults: defaults)) {
                enteredReload.continuation.yield(())
                for await _ in releaseReload.stream {}
            }
        let restore = Task { try await feature.restore(snapshot) }
        var entered = enteredReload.stream.makeAsyncIterator()
        _ = await entered.next()
        #expect(feature.isRestoring)
        do {
            try await feature.restore(snapshot)
            Issue.record("A second restore must be rejected while reload is pending.")
        } catch {
            #expect(error.localizedDescription.contains("already in progress"))
        }
        do {
            try await storage.saveWeight(WeightStore(entries: [current], goalKilograms: nil))
            Issue.record("Edits must not overwrite restored records before reload finishes.")
        } catch {
            #expect(error.localizedDescription.contains("Restore is finishing"))
        }
        #expect(try await storage.loadWeight().entries == [original])
        if cancelCaller {
            restore.cancel()
        } else {
            releaseReload.continuation.finish()
        }
        try await restore.value
        #expect(!feature.isRestoring)
        try await storage.saveWeight(WeightStore(entries: [current], goalKilograms: nil))
        #expect(try await storage.loadWeight().entries == [current])
        await storage.close()
    }

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
