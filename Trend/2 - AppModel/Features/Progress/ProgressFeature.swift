// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

/// Presents the progress feature as a complete capability without exposing the
/// managers that calculate it or the stores that supply its inputs.
@MainActor
@Observable
final class ProgressFeature {
    private let progress: ProgressTracker
    private let weightLogFeature: WeightLogFeature
    private let settings: UserSettingsStore

    init(
        progress: ProgressTracker,
        weightLogFeature: WeightLogFeature,
        settings: UserSettingsStore
    ) {
        self.progress = progress
        self.weightLogFeature = weightLogFeature
        self.settings = settings
    }

    var progressSnapshot: WeightHistoryData { progress.snapshot }
    var goalWeightKilograms: Double? { weightLogFeature.goalKilograms }
    var selectedWeightUnit: WeightUnit { settings.unit }
    var isPreparingProgress: Bool { progress.isLoading }
    var selectedProgressRange: ProgressRange { progress.range }

    func selectProgressRange(_ range: ProgressRange) {
        progress.select(
            range,
            entries: weightLogFeature.entries,
            goalKilograms: weightLogFeature.goalKilograms
        )
    }
}
