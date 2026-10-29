// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct BackupsViewModelTests {
    @Test func acceptedBackupFinishesAfterScreenReleaseThenReleasesItsOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = LocalDataStore(directory: root)
        let entry = WeightEntry(date: .now, kilograms: 70)
        try await storage.saveWeight(WeightStore(entries: [entry], goalKilograms: nil))
        let folder = root.appending(path: "Backups")
        let feature = BackupFeature(storage: storage,
            files: RecoveryBackupFiles(folder: folder, cloudFolder: { nil }),
            settings: UserSettingsStore(cloudSync: PreviewCloudStatus(), defaults: defaults), reload: {})
        var screen: BackupsViewModel? = BackupsViewModel(backups: feature)
        weak var owner = screen
        let action = try #require(screen?.backUp())
        screen = nil
        #expect(owner != nil)
        await action.value
        #expect(owner == nil)
        let saved = try JSONDecoder().decode(RecoverySnapshot.self,
            from: Data(contentsOf: folder.appending(path: "Latest.json")))
        #expect(saved.weight.entries == [entry])
        #expect(feature.status.contains("Backup needs attention"))
        await storage.close()
    }

    @Test func previewRequiresConfirmationBeforeReplacingLocalRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalDataStore(directory: root)
        let original = WeightEntry(date: .now, kilograms: 70)
        try await storage.saveWeight(WeightStore(entries: [original], goalKilograms: nil))
        let snapshot = try await storage.snapshot()
        let current = WeightEntry(date: .now, kilograms: 69)
        try await storage.saveWeight(WeightStore(entries: [current], goalKilograms: nil))
        let file = root.appending(path: "restore.json")
        try JSONEncoder().encode(snapshot).write(to: file)
        var reloads = 0
        let manager = BackupFeature(storage: storage,
            files: RecoveryBackupFiles(folder: root.appending(path: "Backups"), access: PreviewFileAccess(), cloudFolder: { nil }),
            settings: UserSettingsStore(cloudSync: PreviewCloudStatus(), defaults: UserDefaults(suiteName: UUID().uuidString)!)) {
                reloads += 1
            }
        let viewModel = BackupsViewModel(backups: manager)
        await viewModel.inspect(.failure(CocoaError(.fileReadNoPermission))).value
        #expect(viewModel.message != nil)
        #expect(!viewModel.isBusy)
        #expect(viewModel.preview == nil)
        await viewModel.inspect(.success(file)).value
        #expect(viewModel.showsRestoreConfirmation)
        #expect(viewModel.preview?.weight.entries.count == 1)
        #expect(try await storage.loadWeight().entries == [current])
        let firstRestore = viewModel.restore()
        let repeatedRestore = viewModel.restore()
        #expect(viewModel.isBusy)
        await firstRestore.value
        await repeatedRestore.value
        #expect(try await storage.loadWeight().entries == [original])
        #expect(reloads == 1)
        #expect(viewModel.preview == nil)
        #expect(!viewModel.isBusy)
        await storage.close()
    }
}

private struct PreviewFileAccess: BackupFileAccess {
    func replaceSnapshot(_ data: Data, at target: URL) throws { throw CocoaError(.fileWriteNoPermission) }
    func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    func writeNewSnapshot(_ data: Data, to target: URL) throws { throw CocoaError(.fileWriteNoPermission) }
}

private struct PreviewCloudStatus: CloudSyncStatusProviding {
    func cloudStatus() async -> CloudSyncStatus { .unavailable }
}
