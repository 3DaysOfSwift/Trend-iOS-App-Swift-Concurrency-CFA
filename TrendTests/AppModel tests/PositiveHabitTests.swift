// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct PositiveHabitTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func catalogOffersPositiveCheckInsWithoutDeletingRetiredHistory() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { date })
        try await manager.enableSelectedHabits(["coffee", "alcohol", "water"])
        try await manager.recordCoffee()
        #expect(!manager.availableHabits.contains { $0.type == .coffee || $0.type == .alcohol })
        #expect(manager.activeHabits.map(\.id) == ["water"])
        #expect(manager.entries.first?.habitType == .coffee)
    }

    @Test func noAndMissingAreDifferentAndDailyAnswersCanBeCorrected() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { date })
        try await manager.enableSelectedHabits(["gymAttendance", "sauna"])
        #expect(manager.todaysEntry(for: "gymAttendance") == nil)
        try await manager.recordDailyValue(0, for: "gymAttendance")
        #expect(manager.todaysEntry(for: "gymAttendance")?.value == 0)
        #expect(manager.currentWeekSummary(for: "gymAttendance").days.first { $0.isToday }?.hasCheckIn == true)
        #expect(manager.todaysEntry(for: "sauna") == nil)
        try await manager.recordDailyValue(1, for: "gymAttendance")
        #expect(manager.entries.count == 1)
        #expect(manager.todaysEntry(for: "gymAttendance")?.value == 1)
    }

    @Test func morningMoodIsOneReplaceableAnswerPerDay() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { date })
        try await manager.enableSelectedHabits(["morningMood"])
        try await manager.recordDailyValue(2, for: "morningMood")
        try await manager.recordDailyValue(5, for: "morningMood")
        #expect(manager.entries.count == 1)
        #expect(manager.todaysEntry(for: "morningMood")?.value == 5)
        await #expect(throws: (any Error).self) { try await manager.recordDailyValue(6, for: "morningMood") }
        #expect(manager.todaysEntry(for: "morningMood")?.value == 5)
    }

    @Test func multipleCustomHabitsKeepSeparateDailyRecordsAndNames() async throws {
        let store = InMemoryHabitDataStore()
        let manager = HabitsFeature(storage: store, currentDate: { date })
        try await manager.enableSelectedHabits([], customNames: ["Walk outside", "Stretch"])
        let first = manager.activeHabits[0]
        let second = manager.activeHabits[1]
        try await manager.recordDailyValue(1, for: first.id)
        try await manager.recordDailyValue(0, for: second.id)
        #expect(manager.entries.count == 2)
        #expect(manager.todaysEntry(for: first.id)?.value == 1)
        #expect(manager.todaysEntry(for: second.id)?.value == 0)
        try await manager.enableSelectedHabits([second.id])
        let data = try await store.load()
        let decoded = try JSONDecoder().decode(HabitData.self, from: JSONEncoder().encode(data))
        let restored = HabitsFeature(storage: InMemoryHabitDataStore(data: decoded), currentDate: { date })
        await restored.load()
        #expect(restored.activeHabits.map(\.id) == [second.id])
        let entry = try #require(restored.todaysEntry(for: first.id))
        #expect(restored.habit(for: entry).name == "Walk outside")
        #expect(restored.availableHabits.contains { $0.id == first.id })
    }

    @Test func invalidCustomNameDoesNotChangeTheSelection() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { date })
        try await manager.enableSelectedHabits(["water"])
        await #expect(throws: (any Error).self) { try await manager.enableSelectedHabits([], customNames: ["   "]) }
        #expect(manager.enabledHabits.map(\.id) == ["water"])
    }

    @Test func overlappingQuickEntriesAccumulateWithoutLostUpdates() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { date })
        try await manager.enableSelectedHabits(["water", "exerciseSets"])
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { try await manager.recordDailyValue(1, for: "water") }
                group.addTask { try await manager.recordDailyValue(3, for: "exerciseSets") }
            }
            try await group.waitForAll()
        }
        #expect(manager.todaysEntry(for: "water")?.value == 8)
        #expect(manager.todaysEntry(for: "exerciseSets")?.value == 24)
    }

    @Test func quickRunsConvertMilesAndAccumulate() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { date })
        try await manager.enableSelectedHabits(["runningDistance"])
        try await manager.recordDailyValue(1, for: "runningDistance", distanceUnit: .miles)
        try await manager.recordDailyValue(2, for: "runningDistance")
        #expect(manager.todaysEntry(for: "runningDistance")?.value == 3.6)
        #expect(manager.todaysEntry(for: "runningDistance")?.occurrenceCount == 2)
    }

    @Test func tomorrowBeginsWithoutAnAnswer() async throws {
        var now = date
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { now })
        try await manager.enableSelectedHabits(["morningMood"])
        try await manager.recordDailyValue(3, for: "morningMood")
        now = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        await manager.updateCurrentDay()
        #expect(manager.todaysEntry(for: "morningMood") == nil)
        #expect(manager.entries.count == 1)
    }

    @Test func fileStoragePreservesCustomNamesAndIndependentAnswers() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = LocalHabitRepository(storage: LocalDataStore(directory: folder))
        let habit = Habit(customName: "Walk outside")
        let entry = HabitEntry(id: UUID(), habitType: .custom, date: date, value: 1, customHabitID: habit.id)
        var data = HabitData(enabledHabits: [habit], entries: [entry])
        data.customHabits = [habit]
        _ = try await file.savePreferences(selected: data.enabledHabits, custom: data.customHabits)
        _ = try await file.saveEntries(data.entries)
        let reloaded = try await file.load()
        #expect(reloaded.customHabits == [habit])
        #expect(reloaded.enabledHabits == [habit])
        #expect(reloaded.entries == [entry])
    }

    @Test func failedSaveKeepsPreviouslyPublishedState() async throws {
        let manager = HabitsFeature(storage: RejectingHabitSave(), currentDate: { date })
        await manager.load()
        await #expect(throws: (any Error).self) { try await manager.recordDailyValue(1, for: "water") }
        #expect(manager.entries.isEmpty)
        #expect(manager.todaysEntry(for: "water") == nil)
        #expect(manager.loadState == .ready)
    }
}

private actor RejectingHabitSave: HabitDataStore {
    struct SaveFailure: Error {}
    func load() async throws -> HabitData { HabitData(enabledHabits: [Habit(type: .water)], entries: []) }
    func saveEntries(_ entries: [HabitEntry]) async throws -> HabitData { throw SaveFailure() }
    func savePreferences(selected: [Habit], custom: [Habit]) async throws -> HabitData { throw SaveFailure() }
}
