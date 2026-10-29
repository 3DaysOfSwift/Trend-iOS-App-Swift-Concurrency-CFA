// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import SwiftUI
import UniformTypeIdentifiers

struct BackupsView: View {
    @State private var viewModel = BackupsViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        Form {
            Section("Apple iCloud synchronization") {
                Text(viewModel.syncStatus)
            }
            Section {
                Text(viewModel.status)
                Button("Back up now") { viewModel.backUp() }
            } header: { Text("Saved on this iPhone") } footer: {
                Text("SwiftData saves your entries locally and Apple synchronizes them through iCloud. Separately, Trend checks for a recovery backup after edits, on launch and on return. Changed data is backed up at most once every 24 hours, or immediately using Back up now. Latest, previous and weekly recovery copies are kept in iCloud Drive.")
            }
            Section {
                Button("Choose a backup file") { viewModel.choosesFile = true }
            } header: { Text("Restore a backup") } footer: {
                Text("Choose iCloud Drive → Trend → Backups in Files. Each installation has its own folder to preserve older devices’ backups. Restoring replaces current records and these changes also synchronize to iCloud. A local recovery copy is saved before replacement.")
            }
        }
        .disabled(viewModel.isBusy)
        .navigationTitle("Backups")
        .fileImporter(isPresented: $viewModel.choosesFile, allowedContentTypes: [.json]) { result in
            viewModel.inspect(result)
        }
        .alert("Replace local records?", isPresented: $viewModel.showsRestoreConfirmation) {
            Button("Restore", role: .destructive) { viewModel.restore() }
            Button("Cancel", role: .cancel) { viewModel.preview = nil }
        } message: {
            if let backup = viewModel.preview {
                Text("Backup from \(backup.createdAt.formatted()).\n\(backup.weight.entries.count) weight entries, \(backup.habits.entries.count) habit entries and \(backup.habits.enabledHabits.count) selected habits.\nApp \(backup.appVersion ?? "Unknown"), build \(backup.appBuild ?? "Unknown"); backup format \(backup.formatVersion).\nThis replaces your current records and habit selections. These changes also synchronize to iCloud and your other devices.")
            }
        }
        .alert("Trend Backup", isPresented: Binding(get: { viewModel.message != nil }, set: { if !$0 { viewModel.message = nil } })) {
            Button("OK") { viewModel.message = nil }
        } message: { Text(viewModel.message ?? "") }
    }
}
