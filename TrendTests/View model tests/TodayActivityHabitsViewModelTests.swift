// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct TodayActivityHabitsViewModelTests {
    @Test func catalogOffersMeditationAndExcludesRemovedHabits() async throws {
        #expect(Set(Habit.availableHabits.map(\.id)) == ["morningMood", "gymAttendance", "runningDistance", "sauna", "yoga", "meditation"])
        let feature = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { .now })
        try await feature.enableSelectedHabits(["water", "wakeTime", "sleep", "exerciseSets", "gymRepetitions", "yoga", "meditation"])
        #expect(Set(feature.enabledHabits.map(\.id)) == ["yoga", "meditation"])
        let model = TodayActivityHabitsViewModel(feature: feature)
        let meditation = Habit(type: .meditation)
        await model.select(meditation)
        #expect(model.isSelected(meditation))
        await model.select(meditation)
        #expect(!model.isSelected(meditation))
    }

    @Test func activitiesIncludeOnlyEnabledAnswersAndRunningAndToggleBothWays() async throws {
        let feature = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { .now })
        try await feature.enableSelectedHabits(["yoga", "sauna", "runningDistance", "water"])
        let model = TodayActivityHabitsViewModel(feature: feature)
        #expect(Set(model.habits.map(\.id)) == ["yoga", "sauna", "runningDistance"])
        let yoga = Habit(type: .yoga)
        await model.select(yoga)
        #expect(model.isSelected(yoga))
        await model.select(yoga)
        #expect(!model.isSelected(yoga))
        #expect(feature.todaysEntry(for: yoga.id)?.value == 0)
    }

    @Test func runningOnlyHighlightsAfterSuccessfulDistanceSave() async throws {
        let feature = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { .now })
        try await feature.enableSelectedHabits(["runningDistance"])
        let activity = TodayActivityHabitsViewModel(feature: feature)
        let run = Habit(type: .runningDistance)
        await activity.select(run)
        #expect(activity.showsRunEntry)
        #expect(!activity.isSelected(run))
        let editor = RunEntryViewModel(feature: feature)
        editor.distance = -1
        await editor.save()
        #expect(!editor.didSave)
        #expect(!activity.isSelected(run))
        editor.distance = 5
        await editor.save()
        #expect(editor.didSave)
        #expect(activity.isSelected(run))
        #expect(feature.todaysEntry(for: run.id)?.value == 5)
    }
}
