// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Testing
@testable import Trend

@MainActor
struct HabitLibraryViewModelTests {
    @Test func toggleAddsAndRemovesASelection() {
        let viewModel = HabitLibraryViewModel(
            habitsFeature: HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        )

        viewModel.toggle(Habit(type: .gymAttendance))
        #expect(viewModel.selection == [Habit(type: .gymAttendance).id])
        viewModel.toggle(Habit(type: .gymAttendance))
        #expect(viewModel.selection.isEmpty)
    }

    @Test func savePublishesTheSelectedHabits() async {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        let viewModel = HabitLibraryViewModel(habitsFeature: manager)
        viewModel.selection = [Habit(type: .sauna).id, Habit(type: .yoga).id]

        let succeeded = await viewModel.save()

        #expect(succeeded)
        #expect(Set(manager.enabledHabits.map(\.id)) == [Habit(type: .sauna).id, Habit(type: .yoga).id])
    }
}
