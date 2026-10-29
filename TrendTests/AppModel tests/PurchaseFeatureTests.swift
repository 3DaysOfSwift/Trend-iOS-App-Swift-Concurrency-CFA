// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Testing
@testable import Trend

@MainActor
struct PurchaseFeatureTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func releasingFeatureCancelsTransactionObservation(afterUpdate: Bool) async {
        let stopped = AsyncStream<Bool>.makeStream()
        let checked = AsyncStream<Void>.makeStream()
        defer { stopped.continuation.finish(); checked.continuation.finish() }
        let client = InMemoryPurchaseClient { reason in
            if case .cancelled = reason { stopped.continuation.yield(true) }
            else { stopped.continuation.yield(false) }
        }
        client.entitlementResponse = {
            checked.continuation.yield(())
            return true
        }
        var feature: PurchaseFeature? = PurchaseFeature(client: client)
        weak var owner = feature
        feature?.observeTransactionUpdates()
        feature?.observeTransactionUpdates()
        #expect(client.observationCount == 1)
        if afterUpdate {
            client.completePurchaseOutsideThePurchaseSheet()
            var events = checked.stream.makeAsyncIterator()
            _ = await events.next()
        }
        feature = nil
        #expect(owner == nil)
        var termination = stopped.stream.makeAsyncIterator()
        #expect(await termination.next() == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func overlappingRefreshesShareWorkDespiteCallerCancellation() async {
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let joined = AsyncStream<Void>.makeStream()
        defer {
            entered.continuation.finish()
            release.continuation.finish()
            joined.continuation.finish()
        }
        let client = InMemoryPurchaseClient()
        let product = client.product
        var requests = 0
        client.productResponse = {
            requests += 1
            entered.continuation.yield(())
            for await _ in release.stream { break }
            return product
        }
        let feature = PurchaseFeature(client: client)
        var firstFinished = false
        var secondFinished = false
        let first = Task { await feature.refreshStoreState(); firstFinished = true }
        var events = entered.stream.makeAsyncIterator()
        _ = await events.next()
        let second = Task {
            joined.continuation.yield(())
            await feature.refreshStoreState()
            secondFinished = true
        }
        var admission = joined.stream.makeAsyncIterator()
        _ = await admission.next()
        first.cancel()
        #expect(feature.isLoading)
        #expect(!firstFinished && !secondFinished)
        release.continuation.finish()
        await first.value
        await second.value
        #expect(requests == 1)
        #expect(firstFinished && secondFinished)
        #expect(!feature.isLoading)
        #expect(feature.habitsProduct?.id == product.id)
        await feature.refreshStoreState()
        #expect(requests == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func oldStartupEntitlementCannotRelockCompletedPurchase() async {
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); release.continuation.finish() }
        let client = InMemoryPurchaseClient()
        var calls = 0
        client.entitlementResponse = {
            calls += 1
            if calls == 1 {
                entered.continuation.yield(())
                for await _ in release.stream { break }
                return false
            }
            return true
        }
        let feature = PurchaseFeature(client: client)
        let startup = Task { await feature.refreshStoreState() }
        var events = entered.stream.makeAsyncIterator()
        _ = await events.next()
        await feature.purchaseHabits()
        #expect(feature.hasUnlockedHabits)
        release.continuation.yield(())
        await startup.value
        #expect(feature.hasUnlockedHabits)
        #expect(!feature.isLoading)
    }

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
