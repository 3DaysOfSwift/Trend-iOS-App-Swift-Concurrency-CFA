// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Observation
import Foundation

@MainActor
@Observable
final class PurchaseFeature {
    static let habitsProductID = "com.mattharding.Trend.habits"

    private let client: any PurchaseClient
    private var storeRefreshTask: Task<Void, Never>?
    private var transactionUpdatesTask: Task<Void, Never>?

    private(set) var habitsProduct: PurchaseProduct?
    private(set) var hasUnlockedHabits = false
    private(set) var isLoading = true
    private(set) var isPurchasing = false
    private(set) var message: String?
    private(set) var newlyCompletedPurchaseID: UUID?
    private var hasCompletedInitialEntitlementCheck = false
    private var entitlementRequestID = UUID()

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

    /// Repeated callers share the active refresh. A departing caller does not
    /// cancel the store state needed by the rest of the app.
    func refreshStoreState() async {
        if let storeRefreshTask { await storeRefreshTask.value; return }
        isLoading = true
        let task = Task {
            defer { storeRefreshTask = nil; isLoading = false }
            await loadStoreState()
        }
        storeRefreshTask = task
        await task.value
    }

    private func loadStoreState() async {
        let productTask = Task { @MainActor [client] in
            try await client.product(withID: Self.habitsProductID)
        }
        let entitlementTask = Task { @MainActor in
            await refreshEntitlements()
        }

        do { habitsProduct = try await productTask.value }
        catch { message = error.localizedDescription }
        await entitlementTask.value
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
        let requestID = UUID()
        entitlementRequestID = requestID
        let unlocked = await client.hasEntitlement(for: Self.habitsProductID)
        guard entitlementRequestID == requestID else { return }
        hasUnlockedHabits = unlocked
    }

}
