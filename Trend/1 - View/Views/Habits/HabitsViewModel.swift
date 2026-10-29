// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class HabitsViewModel {
    private let habitsFeature: HabitsFeature
    private let purchaseFeature: PurchaseFeature

    var isChoosingHabits = false

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

    func purchaseHabits() async -> Bool {
        let wasAlreadyUnlocked = purchaseFeature.hasUnlockedHabits
        await purchaseFeature.purchaseHabits()
        return !wasAlreadyUnlocked && purchaseFeature.hasUnlockedHabits
    }
    func restorePurchases() async { await purchaseFeature.restorePurchases() }
    func dismissPurchaseMessage() { purchaseFeature.dismissMessage() }
    func loadHabits() async { await habitsFeature.load() }

}
