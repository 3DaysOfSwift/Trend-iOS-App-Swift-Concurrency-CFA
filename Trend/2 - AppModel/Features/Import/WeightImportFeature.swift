// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class WeightImportFeature {
    private let files: WeightImportFileReader
    private let weightLogFeature: WeightLogFeature
    private let refresh: @MainActor () async -> Void

    init(weightLogFeature: WeightLogFeature, files: WeightImportFileReader = WeightImportFileReader(),
         refresh: @escaping @MainActor () async -> Void) {
        self.weightLogFeature = weightLogFeature
        self.files = files
        self.refresh = refresh
    }

    func preview(_ url: URL) async throws -> WeightImportDocument {
        try await files.read(url, timeZone: .current)
    }

    func merge(_ document: WeightImportDocument) async throws -> WeightImportMerge {
        let result = try await weightLogFeature.mergeImportedEntries(document.entries)
        await refresh()
        return result
    }
}

