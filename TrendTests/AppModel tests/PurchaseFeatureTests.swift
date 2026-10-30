// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Testing
@testable import Trend

@MainActor
struct PurchaseFeatureTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func successfulStoreRetryClearsOnlyStoreFailure(pendingPurchase: Bool) async {
        let client = InMemoryPurchaseClient()
        client.productError = TestPurchaseError.productUnavailable
        let feature = PurchaseFeature(client: client)
        await feature.refreshStoreState()
        #expect(feature.message != nil)
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); release.continuation.finish() }
        client.productResponse = {
            entered.continuation.yield(())
            for await _ in release.stream { break }
            return client.product
        }
        let retry = Task { await feature.refreshStoreState() }
        var events = entered.stream.makeAsyncIterator()
        _ = await events.next()
        #expect(feature.isLoading)
        if pendingPurchase {
            client.nextOutcome = .pending
            await feature.purchaseHabits()
        }
        release.continuation.finish()
        await retry.value
        #expect(feature.habitsProduct != nil)
        #expect(!feature.isLoading)
        if pendingPurchase {
            #expect(feature.message == "Your purchase is awaiting approval. Habits will unlock automatically when it completes.")
        } else {
            #expect(feature.message == nil)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func failedOrCancelledCommerceAllowsRetry(restore: Bool, cancel: Bool) async {
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); release.continuation.finish() }
        func failRequest() async throws {
            entered.continuation.yield(())
            for await _ in release.stream { break }
            try Task.checkCancellation()
            throw TestPurchaseError.productUnavailable
        }
        let client = InMemoryPurchaseClient()
        client.purchaseResponse = { try await failRequest(); return .cancelled }
        client.restoreResponse = { try await failRequest() }
        let feature = PurchaseFeature(client: client)
        let request = Task {
            if restore { await feature.restorePurchases() }
            else { await feature.purchaseHabits() }
        }
        var events = entered.stream.makeAsyncIterator()
        _ = await events.next()
        #expect(feature.isPurchasing)
        if cancel { request.cancel() }
        else { release.continuation.finish() }
        await request.value
        #expect(!feature.isPurchasing)
        #expect(!feature.hasUnlockedHabits)
        if cancel { #expect(feature.message == nil) }
        else { #expect(feature.message != nil) }
        client.purchaseResponse = nil
        client.restoreResponse = nil
        if restore {
            client.hasPurchased = true
            await feature.restorePurchases()
            #expect(feature.message == "Trend Habits has been restored.")
        } else {
            await feature.purchaseHabits()
            #expect(feature.message == nil)
        }
        #expect(feature.hasUnlockedHabits)
        #expect(!feature.isPurchasing)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func purchaseAndRestoreExcludeCompetingRequests(restoreFirst: Bool) async {
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); release.continuation.finish() }
        var calls = 0
        func performRequest() async {
            calls += 1
            if calls == 1 {
                entered.continuation.yield(())
                for await _ in release.stream { break }
            }
        }
        let client = InMemoryPurchaseClient()
        client.purchaseResponse = { await performRequest(); return .cancelled }
        client.restoreResponse = { await performRequest() }
        let feature = PurchaseFeature(client: client)
        let first = Task {
            if restoreFirst { await feature.restorePurchases() }
            else { await feature.purchaseHabits() }
        }
        var events = entered.stream.makeAsyncIterator()
        _ = await events.next()
        await feature.purchaseHabits()
        await feature.restorePurchases()
        #expect(calls == 1)
        #expect(feature.isPurchasing)
        release.continuation.finish()
        await first.value
        #expect(!feature.isPurchasing)
        await feature.purchaseHabits()
        #expect(calls == 2)
    }

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
