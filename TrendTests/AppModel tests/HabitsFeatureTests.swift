// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct HabitsFeatureTests {
    @Test func selectionDefinesTheActiveHabitList() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)

        try await manager.enableSelectedHabits([Habit(type: .coffee).id, Habit(type: .water).id])

        #expect(Set(manager.enabledHabits.map(\.id)) == Set([Habit(type: .coffee).id, Habit(type: .water).id]))
    }

    @Test func twoCoffeesOnTheSameDayAccumulate() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        try await manager.enableSelectedHabits([Habit(type: .coffee).id])

        try await manager.recordCoffee(on: date)
        try await manager.recordCoffee(on: date)

        #expect(manager.entries.count == 1)
        #expect(manager.entry(for: Habit(type: .coffee).id, on: date)?.value == 2)
    }

    @Test func removingAndReselectingAHabitPreservesItsHistory() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        try await manager.enableSelectedHabits([Habit(type: .water).id])
        for _ in 0..<6 { try await manager.recordGlassOfWater(on: date) }

        try await manager.enableSelectedHabits([])
        try await manager.enableSelectedHabits([Habit(type: .water).id])

        #expect(manager.entry(for: Habit(type: .water).id, on: date)?.value == 6)
    }

    @Test func separateRunsAccumulateDistanceAndOccurrenceCount() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        try await manager.enableSelectedHabits([Habit(type: .runningDistance).id])

        try await manager.recordRun(kilometres: 3, on: date)
        try await manager.recordRun(kilometres: 2, on: date)

        let entry = manager.entry(for: Habit(type: .runningDistance).id, on: date)
        #expect(entry?.value == 5)
        #expect(entry?.occurrenceCount == 2)
    }

    @Test func clearingTodayRemovesTheHabitEntry() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        try await manager.enableSelectedHabits([Habit(type: .gymRepetitions).id])
        try await manager.recordGymRepetitions(20, on: date)

        try await manager.clearGymRepetitions(on: date)

        #expect(manager.entry(for: Habit(type: .gymRepetitions).id, on: date) == nil)
    }

    @Test func distanceUnitsConvertToAndFromCanonicalKilometres() {
        let kilometres = RunningDistanceUnit.miles.kilometres(from: 1)

        #expect(abs(kilometres - 1.609_344) < 0.000_001)
        #expect(abs(RunningDistanceUnit.miles.value(fromKilometres: kilometres) - 1) < 0.000_001)
    }

    @Test func removingOneDecrementsThenRemovesTheDailyEntry() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        try await manager.enableSelectedHabits([Habit(type: .coffee).id])
        try await manager.recordCoffee(on: date)
        try await manager.recordCoffee(on: date)

        let remainingEntry = try await manager.removeCoffee(on: date)
        #expect(remainingEntry?.value == 1)
        #expect(manager.entry(for: Habit(type: .coffee).id, on: date) == remainingEntry)

        let removedEntry = try await manager.removeCoffee(on: date)
        #expect(removedEntry == nil)
        #expect(manager.entry(for: Habit(type: .coffee).id, on: date) == nil)
    }

    @Test func lifetimeSummaryTotalsEntriesAndKeepsTheFirstDate() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        let firstDate = Date(timeIntervalSince1970: 1_788_480_000)
        let secondDate = firstDate.addingTimeInterval(86_400)
        try await manager.enableSelectedHabits([Habit(type: .coffee).id])
        for _ in 0..<2 { try await manager.recordCoffee(on: firstDate) }
        for _ in 0..<3 { try await manager.recordCoffee(on: secondDate) }

        let summary = manager.lifetimeSummary(for: Habit(type: .coffee).id)

        #expect(summary.totalValue == 5)
        #expect(summary.firstEntryDate == firstDate)
    }

    @Test func weeklySummaryAlwaysRunsFromMondayToSunday() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 12))!
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), calendar: calendar, currentDate: TestAppModelFactory.currentDate)
        try await manager.enableSelectedHabits([Habit(type: .coffee).id])
        try await manager.recordCoffee(on: friday)

        let summary = await manager.weekSummary(for: Habit(type: .coffee).id, on: friday)

        #expect(summary.days.count == 7)
        #expect(calendar.component(.weekday, from: summary.days[0].date) == 2)
        #expect(summary.days[4].isToday)
        #expect(summary.days[4].hasCheckIn)
        #expect(summary.totalValue == 1)
        #expect(summary.currentStreak == 1)
    }

    @Test func appModelRejectsValuesOutsideEachHabitPolicy() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        try await manager.enableSelectedHabits([Habit(type: .sleep).id, Habit(type: .wakeTime).id])

        await #expect(throws: HabitError.self) {
            try await manager.recordSleep(hours: 25, on: date)
        }
        await #expect(throws: HabitError.self) {
            try await manager.recordWakeTime(minutesAfterMidnight: 1_440, on: date)
        }
    }

    @Test func namedCoffeeCommandsKeepTheStoredCountConsistent() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: TestAppModelFactory.currentDate)
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        try await manager.enableSelectedHabits([Habit(type: .coffee).id])

        try await manager.recordCoffee(on: date)
        try await manager.recordCoffee(on: date)
        try await manager.removeCoffee(on: date)

        let entry = manager.entry(for: Habit(type: .coffee).id, on: date)
        #expect(entry?.value == 1)
        #expect(entry?.occurrenceCount == nil)
    }
}
