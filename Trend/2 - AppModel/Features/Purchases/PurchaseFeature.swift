// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Observation
import Foundation

@MainActor
@Observable
final class PurchaseFeature {
    static let habitsProductID = "com.mattharding.Trend.habits"

    private let client: any PurchaseClient
    private var transactionUpdatesTask: Task<Void, Never>?

    private(set) var habitsProduct: PurchaseProduct?
    private(set) var hasUnlockedHabits = false
    private(set) var isLoading = true
    private(set) var isPurchasing = false
    private(set) var message: String?
    private(set) var newlyCompletedPurchaseID: UUID?
    private var hasCompletedInitialEntitlementCheck = false

    init(client: any PurchaseClient) {
        self.client = client
    }

    func observeTransactionUpdates() {
        guard transactionUpdatesTask == nil else { return }
        let updates = client.transactionUpdates()
        transactionUpdatesTask = Task { @MainActor [weak self] in
            for await _ in updates {
                guard let self else { return }
                let wasUnlocked = self.hasUnlockedHabits
                await self.refreshEntitlements()
                if self.hasCompletedInitialEntitlementCheck, !wasUnlocked, self.hasUnlockedHabits {
                    self.newlyCompletedPurchaseID = UUID()
                }
            }
        }
    }

    func refreshStoreState() async {
        isLoading = true
        let productTask = Task { @MainActor [client] in
            try await client.product(withID: Self.habitsProductID)
        }
        let entitlementTask = Task { @MainActor [client] in
            await client.hasEntitlement(for: Self.habitsProductID)
        }

        do { habitsProduct = try await productTask.value }
        catch { message = error.localizedDescription }
        hasUnlockedHabits = await entitlementTask.value
        isLoading = false
        hasCompletedInitialEntitlementCheck = true
    }

    func purchaseHabits() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await client.purchase(productID: Self.habitsProductID) {
            case .purchased:
                await refreshEntitlements()
            case .pending:
                message = "Your purchase is awaiting approval. Habits will unlock automatically when it completes."
            case .cancelled:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await client.restore()
            await refreshEntitlements()
            message = hasUnlockedHabits
                ? "Trend Habits has been restored."
                : "No previous Trend Habits purchase was found."
        } catch {
            message = error.localizedDescription
        }
    }

    func dismissMessage() { message = nil }

    private func refreshEntitlements() async {
        hasUnlockedHabits = await client.hasEntitlement(for: Self.habitsProductID)
    }

}
