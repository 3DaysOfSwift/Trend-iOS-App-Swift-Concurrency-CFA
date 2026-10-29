// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation
import Testing
import os
@testable import Trend

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HabitsWorkerIntegrationTests {
    @Test func overlappingLoadsShareOneLoadEvenIfACallerCancels() async {
        await checkSharedLoad(failing: false)
    }

    @Test func overlappingLoadsShareFailureAndAllowAnotherLoad() async {
        await checkSharedLoad(failing: true)
    }

    private func checkSharedLoad(failing: Bool) async {
        let dataStore = SuspendedHabitDataStore()
        let manager = HabitsFeature(storage: dataStore, currentDate: TestAppModelFactory.currentDate)
        await dataStore.pauseNextLoad()
        var started = 0
        var finished = 0
        let callers = (0..<4).map { _ in
            Task {
                started += 1
                await manager.load()
                if failing {
                    #expect(manager.errorMessage != nil)
                } else {
                    #expect(manager.loadState == .ready)
                }
                finished += 1
            }
        }
        await dataStore.waitForPausedLoad()
        while started < 4 { await Task.yield() }
        #expect(finished == 0)
        #expect(await dataStore.loadCount == 1)
        callers[0].cancel()
        await dataStore.releaseLoad(failing: failing)
        for caller in callers { await caller.value }
        #expect(finished == 4)
        #expect(await dataStore.loadCount == 1)

        await manager.load()
        #expect(await dataStore.loadCount == (failing ? 2 : 1))
        #expect(manager.loadState == .ready)
        #expect(manager.errorMessage == nil)
    }

    @Test func overlappingRecordingsPreserveBothValues() async throws {
        let dataStore = SuspendedHabitDataStore()
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        let manager = HabitsFeature(storage: dataStore, currentDate: { date })
        try await manager.enableSelectedHabits([Habit(type: .runningDistance).id])
        await dataStore.pauseNextSave()
        let first = Task { try await manager.recordRun(kilometres: 1) }
        await dataStore.waitForPausedSave()
        let second = Task { try await manager.recordRun(kilometres: 1) }
        #expect(manager.entries.isEmpty)
        await dataStore.releaseSave()
        let firstEntry = try await first.value
        let secondEntry = try await second.value
        #expect(firstEntry.value == 1)
        #expect(secondEntry.value == 2)
        #expect(firstEntry.id != secondEntry.id)
        #expect(manager.todaysEntry(for: Habit(type: .runningDistance).id) == secondEntry)
        #expect(manager.todaysEntry(for: Habit(type: .runningDistance).id)?.value == 2)
        #expect(manager.currentWeekSummary(for: Habit(type: .runningDistance).id).totalValue == 2)
        let saved = try await dataStore.load()
        #expect(saved.entries.first?.value == 2)
    }

    @Test func loadingAfterARecordingKeepsTheSavedData() async throws {
        let dataStore = SuspendedHabitDataStore()
        let manager = HabitsFeature(storage: dataStore, currentDate: TestAppModelFactory.currentDate)
        try await manager.enableSelectedHabits([Habit(type: .runningDistance).id])
        await dataStore.pauseNextSave()
        let recording = Task { try await manager.recordRun(kilometres: 1) }
        await dataStore.waitForPausedSave()
        let refresh = Task { await manager.load() }
        await dataStore.releaseSave()
        try await recording.value
        await refresh.value
        #expect(manager.entries.first?.value == 1)
        #expect(manager.loadState == .ready)
    }

    @Test func failedSavePreservesPublishedValuesAndAllowsTheNextOperation() async throws {
        let dataStore = SuspendedHabitDataStore()
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        let manager = HabitsFeature(storage: dataStore, currentDate: { date })
        try await manager.enableSelectedHabits([Habit(type: .runningDistance).id])
        try await manager.recordRun(kilometres: 1)
        await dataStore.pauseNextSave()
        let failed = Task { try await manager.recordRun(kilometres: 1) }
        await dataStore.waitForPausedSave()
        await dataStore.releaseSave(failing: true)
        do {
            try await failed.value
            #expect(false)
        } catch {}
        #expect(manager.todaysEntry(for: Habit(type: .runningDistance).id)?.value == 1)
        #expect(manager.currentWeekSummary(for: Habit(type: .runningDistance).id).totalValue == 1)
        try await manager.recordRun(kilometres: 1)
        #expect(manager.todaysEntry(for: Habit(type: .runningDistance).id)?.value == 2)
    }

    @Test func cancelledQueuedRecordingDoesNotWrite() async throws {
        let dataStore = SuspendedHabitDataStore()
        let manager = HabitsFeature(storage: dataStore, currentDate: TestAppModelFactory.currentDate)
        try await manager.enableSelectedHabits([Habit(type: .runningDistance).id])
        await dataStore.pauseNextSave()
        let first = Task { try await manager.recordRun(kilometres: 1) }
        await dataStore.waitForPausedSave()
        let cancelled = Task { try await manager.recordRun(kilometres: 1) }
        cancelled.cancel()
        await dataStore.releaseSave()
        try await first.value
        do {
            try await cancelled.value
            #expect(false)
        } catch {}
        #expect(manager.entries.first?.value == 1)
    }

    @Test func changingDayRecalculatesSummariesWithoutLoadingStorage() async throws {
        let dataStore = SuspendedHabitDataStore()
        var date = Date(timeIntervalSince1970: 1_788_480_000)
        let manager = HabitsFeature(storage: dataStore, currentDate: { date })
        try await manager.enableSelectedHabits([Habit(type: .runningDistance).id])
        try await manager.recordRun(kilometres: 1)
        let loadsBeforeDayChange = await dataStore.loadCount
        date = date.addingTimeInterval(2 * 86_400)
        await manager.updateCurrentDay()
        #expect(manager.todaysEntry(for: Habit(type: .runningDistance).id) == nil)
        #expect(manager.currentWeekSummary(for: Habit(type: .runningDistance).id).currentStreak == 0)
        #expect(await dataStore.loadCount == loadsBeforeDayChange)
    }

    @Test func loadingPublishesPreparedSummaries() async throws {
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        let data = HabitData(enabledHabits: [Habit(type: .runningDistance)], entries: [
            HabitEntry(id: UUID(), habitType: .runningDistance, date: date, value: 3)
        ])
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(data: data), currentDate: { date })
        await manager.load()
        #expect(manager.loadState == .ready)
        #expect(manager.todaysEntry(for: Habit(type: .runningDistance).id)?.value == 3)
        #expect(manager.currentWeekSummary(for: Habit(type: .runningDistance).id).totalValue == 3)
        #expect(manager.lifetimeSummary(for: Habit(type: .runningDistance).id).totalValue == 3)
    }

    @Test func successfulSaveStillPublishesWhenCancellationArrivesDuringPersistence() async throws {
        let dataStore = SuspendedHabitDataStore()
        let manager = HabitsFeature(storage: dataStore, currentDate: TestAppModelFactory.currentDate)
        try await manager.enableSelectedHabits([Habit(type: .runningDistance).id])
        await dataStore.pauseNextSave()
        let recording = Task { try await manager.recordRun(kilometres: 1) }
        await dataStore.waitForPausedSave()
        recording.cancel()
        await dataStore.releaseSave()
        try await recording.value
        #expect(manager.entries.first?.value == 1)
        let saved = try await dataStore.load()
        #expect(saved.entries == manager.entries)
    }

    @Test func swiftUIObservationTracksSharedFeatureState() async throws {
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { date })
        try await manager.enableSelectedHabits([Habit(type: .runningDistance).id])
        let viewModel = DailyHabitsViewModel(habitsFeature: manager,
            purchaseFeature: PurchaseFeature(client: InMemoryPurchaseClient()))
        let habit = Habit(type: .runningDistance)
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = viewModel.week(for: habit)
        } onChange: {
            changed.withLock { $0 = true }
        }
        let history = HabitHistoryViewModel(habitsFeature: manager)
        let historyChanged = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = history.entries
        } onChange: {
            historyChanged.withLock { $0 = true }
        }
        let selectionChanged = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = manager.enabledHabits
        } onChange: {
            selectionChanged.withLock { $0 = true }
        }
        try await manager.recordRun(kilometres: 1)
        #expect(historyChanged.withLock { $0 })
        #expect(selectionChanged.withLock { $0 })
        #expect(history.entries.count == 1)
        #expect(changed.withLock { $0 })
        #expect(viewModel.week(for: habit).currentStreak == 1)
        #expect(viewModel.value(for: habit) == 1)
    }
}

private actor SuspendedHabitDataStore: HabitDataStore {
    private var data = HabitData(enabledHabits: [], entries: [])
    private var pauseLoad = false
    private var loadRelease: CheckedContinuation<Void, Never>?
    private var loadStarted: CheckedContinuation<Void, Never>?
    private var failLoad = false
    private var pauseSave = false
    private var saveRelease: CheckedContinuation<Void, Never>?
    private var saveStarted: CheckedContinuation<Void, Never>?
    private var failSave = false
    private(set) var loadCount = 0

    func savePreferences(selected: [Habit], custom: [Habit]) async throws -> HabitData {
        var candidate = data
        candidate.enabledHabits = selected
        candidate.customHabits = custom
        return try await saveData(candidate)
    }

    func saveEntries(_ entries: [HabitEntry]) async throws -> HabitData {
        var candidate = data
        candidate.entries = entries
        return try await saveData(candidate)
    }

    func load() async throws -> HabitData {
        loadCount += 1
        if pauseLoad {
            pauseLoad = false
            await withCheckedContinuation { continuation in
                loadRelease = continuation
                loadStarted?.resume()
                loadStarted = nil
            }
            if failLoad {
                failLoad = false
                throw CocoaError(.fileReadUnknown)
            }
        }
        return data
    }

    private func saveData(_ data: HabitData) async throws -> HabitData {
        if pauseSave {
            pauseSave = false
            await withCheckedContinuation { continuation in
                saveRelease = continuation
                saveStarted?.resume()
                saveStarted = nil
            }
            if failSave {
                failSave = false
                throw CocoaError(.fileWriteUnknown)
            }
        }
        self.data = data
        return data
    }

    func pauseNextLoad() { pauseLoad = true }

    func waitForPausedLoad() async {
        if loadRelease != nil { return }
        await withCheckedContinuation { loadStarted = $0 }
    }

    func releaseLoad(failing: Bool = false) {
        failLoad = failing
        loadRelease?.resume()
        loadRelease = nil
    }

    func pauseNextSave() { pauseSave = true }

    func waitForPausedSave() async {
        if saveRelease != nil { return }
        await withCheckedContinuation { saveStarted = $0 }
    }

    func releaseSave(failing: Bool = false) {
        failSave = failing
        saveRelease?.resume()
        saveRelease = nil
    }
}
