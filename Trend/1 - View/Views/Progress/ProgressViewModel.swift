// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class ProgressViewModel {
    private let progressFeature: ProgressFeature

    init(progressFeature: ProgressFeature = AppModel.shared.progressFeature) {
        self.progressFeature = progressFeature
    }

    var snapshot: WeightHistoryData { progressFeature.progressSnapshot }
    var goalKilograms: Double? { progressFeature.goalWeightKilograms }
    var unit: WeightUnit { progressFeature.selectedWeightUnit }
    var isLoading: Bool { progressFeature.isPreparingProgress }
    var range: ProgressRange {
        get { progressFeature.selectedProgressRange }
        set { progressFeature.selectProgressRange(newValue) }
    }
}
