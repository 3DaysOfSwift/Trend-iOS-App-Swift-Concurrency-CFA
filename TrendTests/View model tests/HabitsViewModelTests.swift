// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct HabitsViewModelTests {
    @Test func purchaseReportsOnlyANewUnlockAsNew() async {
        let purchaseManager = PurchaseFeature(client: InMemoryPurchaseClient())
        let viewModel = HabitsViewModel(
            habitsFeature: HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate),
            purchaseFeature: purchaseManager
        )

        #expect(await viewModel.purchaseHabits())
        #expect(!(await viewModel.purchaseHabits()))
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
