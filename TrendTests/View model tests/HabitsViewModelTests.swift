// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct HabitsViewModelTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func acceptedInteractionCompletesAfterScreenRelease(restore: Bool) async throws {
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); release.continuation.finish() }
        let client = InMemoryPurchaseClient()
        var requests = 0
        func waitForCompletion() async {
            requests += 1
            entered.continuation.yield(())
            for await _ in release.stream { break }
            client.hasPurchased = true
        }
        client.purchaseResponse = { await waitForCompletion(); return .purchased }
        client.restoreResponse = { await waitForCompletion() }
        let purchaseFeature = PurchaseFeature(client: client)
        var viewModel: HabitsViewModel? = HabitsViewModel(
            habitsFeature: HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate),
            purchaseFeature: purchaseFeature)
        weak var owner = viewModel
        let task = try #require(restore ? viewModel?.restorePurchases() : viewModel?.purchaseHabits())
        let repeated = try #require(restore ? viewModel?.restorePurchases() : viewModel?.purchaseHabits())
        var events = entered.stream.makeAsyncIterator()
        _ = await events.next()
        viewModel = nil
        #expect(owner != nil)
        #expect(purchaseFeature.isPurchasing)
        release.continuation.finish()
        await task.value
        await repeated.value
        #expect(requests == 1)
        #expect(purchaseFeature.hasUnlockedHabits)
        #expect(!purchaseFeature.isPurchasing)
        #expect(owner == nil)
    }

    @Test func purchaseReportsOnlyANewUnlockAsNew() async {
        let purchaseManager = PurchaseFeature(client: InMemoryPurchaseClient())
        let viewModel = HabitsViewModel(
            habitsFeature: HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate),
            purchaseFeature: purchaseManager
        )

        await viewModel.purchaseHabits().value
        #expect(viewModel.showsPurchaseJourney)
        viewModel.showsPurchaseJourney = false
        await viewModel.purchaseHabits().value
        #expect(!viewModel.showsPurchaseJourney)
    }

    @Test func dashboardReflectsSelectedHabits() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        let habit = Habit(type: .yoga)
        let viewModel = HabitsViewModel(
            habitsFeature: manager,
            purchaseFeature: PurchaseFeature(client: InMemoryPurchaseClient())
        )
        #expect(viewModel.habits.isEmpty)
        try await manager.enableSelectedHabits([habit.id])
        #expect(viewModel.habits == [habit])
        try await manager.enableSelectedHabits([])
        #expect(viewModel.habits.isEmpty)
    }
}
