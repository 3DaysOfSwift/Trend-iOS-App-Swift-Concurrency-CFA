// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation
import CoreData

@MainActor @Observable
final class BackupFeature {
    private let storage: LocalDataStore
    private let files: any RecoveryBackupProviding
    private let settings: UserSettingsStore
    private let reload: @MainActor () async -> Void
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var backupTask: Task<Void, Never>?
    @ObservationIgnored private var backupRequested = false
    @ObservationIgnored private var forceRequested = false
    @ObservationIgnored private var cloudObservation: Task<Void, Never>?
    private(set) var syncStatus = "iCloud synchronization has not reported a result yet."
    private(set) var status = "Local storage. Backup not checked yet."
    private(set) var isRestoring = false

    init(storage: LocalDataStore, files: any RecoveryBackupProviding, settings: UserSettingsStore,
         reload: @escaping @MainActor () async -> Void) {
        self.storage = storage
        self.files = files
        self.settings = settings
        self.reload = reload
    }

    /// Explicit launch work. Initializers never load data or start uploads.
    func observeLocalChanges() {
        guard observation == nil else { return }
        observation = Task { [weak self, changes = storage.changes] in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                await self?.triggerDataBackupIfNeeded()
            }
        }
    }

    /// Observe Apple's completed imports so feature state reflects downloaded
    /// records without requiring the user to leave and reopen the screen.
    func observeCloudChanges() {
        guard cloudObservation == nil else { return }
        let events = NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
            .compactMap { notification -> CloudImportResult? in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return nil }
                return CloudImportResult(imported: event.type == .import && event.succeeded,
                    message: event.error.map { "iCloud sync needs attention: \($0.localizedDescription)" }
                        ?? (event.succeeded
                            ? (event.type == .import ? "An iCloud download completed." :
                                event.type == .export ? "An iCloud upload completed." : "iCloud synchronization configured.")
                            : "iCloud synchronization is pending."))
            }
        cloudObservation = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                self.syncStatus = event.message
                if event.imported {
                    await self.reload()
                    await self.triggerDataBackupIfNeeded()
                }
            }
        }
    }

    func backUpNow() async { await triggerDataBackupIfNeeded(force: true) }

    /// Lifecycle and edits request a check; the file policy decides whether a
    /// new daily recovery snapshot is due. This does not force CloudKit to sync.
    func triggerDataBackupIfNeeded(force: Bool = false) async {
        backupRequested = true
        forceRequested = forceRequested || force
        if let backupTask { await backupTask.value; return }
        let task = Task {
            defer { backupTask = nil }
            repeat {
                backupRequested = false
                let force = forceRequested
                forceRequested = false
                do {
                    var snapshot = try await storage.snapshot()
                    snapshot.weightUnit = settings.unit
                    guard snapshot.hasData else {
                        status = "No local records to back up. Existing iCloud backups are untouched."
                        continue
                    }
                    let file = try await files.prepareBackupIfNeeded(snapshot, force: force)
                    status = "Saved on this iPhone. Uploading recovery backup…"
                    let uploaded = try await files.uploadPreparedBackup(file)
                    status = uploaded ? "Recovery backup uploaded to iCloud." : "Saved on this iPhone. iCloud upload pending."
                } catch { status = "Backup needs attention: \(error.localizedDescription)" }
            } while backupRequested
        }
        backupTask = task
        await task.value
    }

    func preview(_ url: URL) async throws -> RecoverySnapshot { try await files.preview(url) }

    func restore(_ snapshot: RecoverySnapshot) async throws {
        guard !isRestoring else { throw StoreError.failure("A restore is already in progress.") }
        isRestoring = true
        defer { isRestoring = false }
        try await storage.restore(snapshot)
        if let unit = snapshot.weightUnit { settings.unit = unit }
        await reload()
        await storage.finishRestore()
        status = "Backup restored. A pre-restore copy remains on this iPhone."
    }
}

private struct CloudImportResult: Sendable {
    let imported: Bool
    let message: String
}
