// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

struct WeightImportSelection: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor @Observable
final class WeightImportViewModel {
    private let feature: WeightImportFeature
    let url: URL
    private(set) var document: WeightImportDocument?
    private(set) var isLoading = false
    private(set) var isImporting = false
    private(set) var result: WeightImportMerge?
    private(set) var errorMessage: String?

    init(url: URL, feature: WeightImportFeature = AppModel.shared.weightImportFeature) {
        self.url = url
        self.feature = feature
    }

    var canImport: Bool { document != nil && !isLoading && !isImporting && result == nil }
    var filename: String { url.lastPathComponent }
    var source: String { document?.source ?? "Weight import" }
    var count: Int { document?.entries.count ?? 0 }
    var explanation: String { document?.explanation ?? "" }
    var dateRange: String {
        guard let entries = document?.entries, let first = entries.map(\.date).min(),
              let last = entries.map(\.date).max() else { return "" }
        return "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"
    }
    var sample: [WeightEntry] { Array((document?.entries ?? []).sorted { $0.date > $1.date }.prefix(5)) }
    var completionMessage: String {
        guard let result else { return "" }
        return "\(result.additions.count) entries added. \(result.skipped) matching entries skipped."
    }

    func load() async {
        guard document == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await feature.preview(url)
            try Task.checkCancellation()
            document = loaded
        } catch is CancellationError { } catch { errorMessage = error.localizedDescription }
    }

    func importEntries() async {
        guard canImport, let document else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do { result = try await feature.merge(document) }
        catch { errorMessage = error.localizedDescription }
    }
}

