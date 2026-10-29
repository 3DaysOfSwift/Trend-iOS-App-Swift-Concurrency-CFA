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

    @Test(arguments: [true, false])
    func failedUploadPreservesLocalBackupAndRetriesWithoutAnotherArchive(failWeekly: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = LocalDataStore(directory: root.appending(path: "Store"))
        let entry = WeightEntry(date: .now, kilograms: 70)
        try await storage.saveWeight(WeightStore(entries: [entry], goalKilograms: nil))
        let blocked = root.appending(path: "upload-blocked")
        try Data().write(to: blocked)
        let local = root.appending(path: "Backups")
        let cloud = root.appending(path: "Cloud")
        let feature = BackupFeature(storage: storage,
            files: RecoveryBackupFiles(folder: local,
                access: RetryableBackupAccess(blocked: blocked, failWeekly: failWeekly), cloudFolder: { cloud }),
            settings: UserSettingsStore(cloudSync: OfflineCloudStatus(), defaults: defaults), reload: {})
        await feature.backUpNow()
        #expect(feature.status.contains("Backup needs attention"))
        let bytes = try Data(contentsOf: local.appending(path: "Latest.json"))
        #expect(try JSONDecoder().decode(RecoverySnapshot.self, from: bytes).weight.entries == [entry])
        let archives = try FileManager.default.contentsOfDirectory(at: local.appending(path: "Weekly"), includingPropertiesForKeys: nil)
        #expect(archives.count == 1)
        try FileManager.default.removeItem(at: blocked)
        await feature.triggerDataBackupIfNeeded()
        #expect(feature.status == "Saved on this iPhone. iCloud upload pending.")
        #expect(try Data(contentsOf: local.appending(path: "Latest.json")) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(at: local.appending(path: "Weekly"), includingPropertiesForKeys: nil) == archives)
        #expect(!FileManager.default.fileExists(atPath: local.appending(path: "Previous.json").path))
        let installation = try String(contentsOf: local.appending(path: "Installation.txt"), encoding: .utf8)
        #expect(try Data(contentsOf: cloud.appending(path: "Backups/\(installation)/Latest.json")) == bytes)
        #expect(try await storage.loadWeight().entries == [entry])
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

private struct RetryableBackupAccess: BackupFileAccess {
    let blocked: URL
    let failWeekly: Bool

    func replaceSnapshot(_ data: Data, at target: URL) throws {
        if FileManager.default.fileExists(atPath: blocked.path) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try data.write(to: target, options: .atomic)
    }

    func writeNewSnapshot(_ data: Data, to target: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            guard try Data(contentsOf: target) == data else {
                throw CocoaError(.fileWriteFileExists)
            }
            return
        }
        if failWeekly {
            try replaceSnapshot(data, at: target)
        } else {
            try data.write(to: target, options: .atomic)
        }
    }

    func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
}
