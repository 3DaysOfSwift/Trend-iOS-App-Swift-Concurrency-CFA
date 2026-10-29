// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct HabitHistoryViewModelTests {
    @Test func formatsNumericHistoryWithItsUnit() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        try await manager.enableSelectedHabits([Habit(type: .water).id])
        for _ in 0..<6 { try await manager.recordGlassOfWater(on: .now) }
        let viewModel = HabitHistoryViewModel(habitsFeature: manager)

        #expect(viewModel.valueDescription(for: manager.entries[0]) == "6 glasses")
    }

    @Test func resolvesDeselectedHabitFromItsType() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        try await manager.enableSelectedHabits([Habit(type: .coffee).id])
        try await manager.recordCoffee(on: .now)
        try await manager.enableSelectedHabits([])
        let viewModel = HabitHistoryViewModel(habitsFeature: manager)

        #expect(viewModel.habit(for: manager.entries[0]).name == "Coffee")
    }
}
