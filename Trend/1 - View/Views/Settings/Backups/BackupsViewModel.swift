// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor @Observable
final class BackupsViewModel {
    private let backups: BackupFeature
    var preview: RecoverySnapshot?
    var showsRestoreConfirmation = false
    var choosesFile = false
    var message: String?
    private(set) var isBusy = false

    init(backups: BackupFeature = AppModel.shared.backupFeature) { self.backups = backups }
    var status: String { backups.status }
    var syncStatus: String { backups.syncStatus }

    func backUp() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await backups.backUpNow()
    }

    func inspect(_ result: Result<URL, Error>) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            preview = try await backups.preview(result.get())
            showsRestoreConfirmation = true
        } catch { message = error.localizedDescription }
    }

    func restore() async {
        guard !isBusy, let preview else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await backups.restore(preview)
            self.preview = nil
            message = "Your backup has been restored."
        } catch { message = error.localizedDescription }
    }
}
