// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Testing
@testable import Trend

@MainActor
struct PurchaseFeatureTests {
    @Test func storeRefreshLoadsProductWithoutInventingAnEntitlement() async {
        let client = InMemoryPurchaseClient()
        let manager = PurchaseFeature(client: client)

        manager.observeTransactionUpdates()
        await manager.refreshStoreState()

        #expect(manager.habitsProduct?.displayName == "Trend Habits")
        #expect(!manager.hasUnlockedHabits)
        #expect(!manager.isLoading)
    }

    @Test func completedPurchaseUnlocksHabits() async {
        let client = InMemoryPurchaseClient()
        let manager = PurchaseFeature(client: client)
        manager.observeTransactionUpdates()
        await manager.refreshStoreState()

        await manager.purchaseHabits()

        #expect(manager.hasUnlockedHabits)
    }

    @Test func cancelledPurchaseLeavesHabitsLocked() async {
        let client = InMemoryPurchaseClient()
        client.nextOutcome = .cancelled
        let manager = PurchaseFeature(client: client)
        manager.observeTransactionUpdates()
        await manager.refreshStoreState()

        await manager.purchaseHabits()

        #expect(!manager.hasUnlockedHabits)
        #expect(manager.message == nil)
    }

    @Test func entitlementLoadsWhenProductMetadataFails() async {
        let client = InMemoryPurchaseClient()
        client.hasPurchased = true
        client.productError = TestPurchaseError.productUnavailable
        let manager = PurchaseFeature(client: client)

        await manager.refreshStoreState()

        #expect(manager.hasUnlockedHabits)
        #expect(manager.habitsProduct == nil)
        #expect(manager.message != nil)
    }

    @Test func restoreReadsTheCustomersExistingEntitlement() async {
        let client = InMemoryPurchaseClient()
        client.hasPurchased = true
        let manager = PurchaseFeature(client: client)

        await manager.restorePurchases()

        #expect(manager.hasUnlockedHabits)
        #expect(manager.message == "Trend Habits has been restored.")
    }

    @Test func delayedApprovalPublishesANewPurchaseEvent() async {
        let client = InMemoryPurchaseClient()
        let manager = PurchaseFeature(client: client)
        manager.observeTransactionUpdates()
        await manager.refreshStoreState()

        client.completePurchaseOutsideThePurchaseSheet()
        for _ in 0..<10 where manager.newlyCompletedPurchaseID == nil {
            await Task.yield()
        }

        #expect(manager.hasUnlockedHabits)
        #expect(manager.newlyCompletedPurchaseID != nil)
    }
}

private enum TestPurchaseError: Error {
    case productUnavailable
}
