// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class HabitsViewModel {
    private let habitsFeature: HabitsFeature
    private let purchaseFeature: PurchaseFeature

    @ObservationIgnored private var interactionTask: Task<Void, Never>?
    var isChoosingHabits = false
    var showsPurchaseJourney = false

    init(
        habitsFeature: HabitsFeature = AppModel.shared.habitsFeature,
        purchaseFeature: PurchaseFeature = AppModel.shared.purchaseFeature
    ) {
        self.habitsFeature = habitsFeature
        self.purchaseFeature = purchaseFeature
    }

    var habits: [Habit] { habitsFeature.activeHabits }
    var habitLoadState: HabitsFeature.HabitLoadState { habitsFeature.loadState }
    var hasUnlockedHabits: Bool { purchaseFeature.hasUnlockedHabits }
    var isLoadingPurchase: Bool { purchaseFeature.isLoading }
    var isPurchasing: Bool { purchaseFeature.isPurchasing }
    var purchaseMessage: String? { purchaseFeature.message }
    var newlyCompletedPurchaseID: UUID? { purchaseFeature.newlyCompletedPurchaseID }
    var unlockTitle: String {
        guard let product = purchaseFeature.habitsProduct else { return "Unlock Habits" }
        return "Unlock Habits \(product.displayPrice)"
    }
    var productPrice: String { purchaseFeature.habitsProduct?.displayPrice ?? "One-time purchase" }

    @discardableResult
    func purchaseHabits() -> Task<Void, Never> {
        performInteraction {
            guard !self.purchaseFeature.isPurchasing else { return }
            let wasAlreadyUnlocked = self.purchaseFeature.hasUnlockedHabits
            await self.purchaseFeature.purchaseHabits()
            if !wasAlreadyUnlocked && self.purchaseFeature.hasUnlockedHabits {
                self.showsPurchaseJourney = true
            }
        }
    }

    @discardableResult
    func restorePurchases() -> Task<Void, Never> {
        performInteraction { await self.purchaseFeature.restorePurchases() }
    }

    func purchaseCompleted(_ completionID: UUID?) {
        guard completionID != nil, !isPurchasing else { return }
        showsPurchaseJourney = true
    }

    private func performInteraction(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        if let interactionTask { return interactionTask }
        let task = Task {
            defer { interactionTask = nil }
            await operation()
        }
        interactionTask = task
        return task
    }

    func dismissPurchaseMessage() { purchaseFeature.dismissMessage() }
    func loadHabits() async { await habitsFeature.load() }

}
