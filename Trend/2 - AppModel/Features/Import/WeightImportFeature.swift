// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class WeightImportFeature {
    private let files: WeightImportFileReader
    private let weightLog: WeightLogManager
    private let refresh: @MainActor () async -> Void

    init(weightLog: WeightLogManager, files: WeightImportFileReader = WeightImportFileReader(),
         refresh: @escaping @MainActor () async -> Void) {
        self.weightLog = weightLog
        self.files = files
        self.refresh = refresh
    }

    func preview(_ url: URL) async throws -> WeightImportDocument {
        try await files.read(url, timeZone: .current)
    }

    func merge(_ document: WeightImportDocument) async throws -> WeightImportMerge {
        let result = try await weightLog.mergeImportedEntries(document.entries)
        await refresh()
        return result
    }
}

