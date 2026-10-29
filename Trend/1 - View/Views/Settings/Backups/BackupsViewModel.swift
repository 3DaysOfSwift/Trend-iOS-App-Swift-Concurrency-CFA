// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor @Observable
final class BackupsViewModel {
    private let backups: BackupFeature
    @ObservationIgnored private var action: Task<Void, Never>?
    var preview: RecoverySnapshot?
    var showsRestoreConfirmation = false
    var choosesFile = false
    var message: String?
    private(set) var isBusy = false

    init(backups: BackupFeature = AppModel.shared.backupFeature) { self.backups = backups }
    var status: String { backups.status }
    var syncStatus: String { backups.syncStatus }

    @discardableResult
    func backUp() -> Task<Void, Never> {
        perform { await self.backups.backUpNow() }
    }

    /// The accepted operation finishes even if its screen is dismissed.
    /// The busy screen cannot admit another operation until it settles.
    private func perform(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        if let action { return action }
        isBusy = true
        let task = Task {
            defer { isBusy = false; action = nil }
            await operation()
        }
        action = task
        return task
    }

    @discardableResult
    func inspect(_ result: Result<URL, Error>) -> Task<Void, Never> {
        perform { await self.inspectFile(result) }
    }

    private func inspectFile(_ result: Result<URL, Error>) async {
        do {
            preview = try await backups.preview(result.get())
            showsRestoreConfirmation = true
        } catch { message = error.localizedDescription }
    }

    @discardableResult
    func restore() -> Task<Void, Never> {
        perform { await self.restorePreview() }
    }

    private func restorePreview() async {
        guard let preview else { return }
        do {
            try await backups.restore(preview)
            self.preview = nil
            message = "Your backup has been restored."
        } catch { message = error.localizedDescription }
    }
}
