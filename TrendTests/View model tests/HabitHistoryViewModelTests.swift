// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct HabitHistoryViewModelTests {
    @Test func formatsNumericHistoryWithItsUnit() async throws {
        let historical = HabitEntry(id: UUID(), habitType: .water, date: .now, value: 6)
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(data: HabitData(enabledHabits: [], entries: [historical])), currentDate: TestAppModelFactory.currentDate)
        await manager.load()
        let viewModel = HabitHistoryViewModel(habitsFeature: manager)

        #expect(viewModel.valueDescription(for: manager.entries[0]) == "6 glasses")
    }

    @Test func resolvesDeselectedHabitFromItsType() async throws {
        let historical = HabitEntry(id: UUID(), habitType: .coffee, date: .now, value: 1)
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(data: HabitData(enabledHabits: [Habit(type: .coffee)], entries: [historical])), currentDate: TestAppModelFactory.currentDate)
        await manager.load()
        try await manager.enableSelectedHabits([])
        let viewModel = HabitHistoryViewModel(habitsFeature: manager)

        #expect(viewModel.habit(for: manager.entries[0]).name == "Coffee")
    }
}
