// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class HabitsFeature {
    private let worker: HabitsWorker
    private let calendar: Calendar
    private let currentDate: @MainActor () -> Date
    @ObservationIgnored private var loadingTask: Task<Void, Never>?
    @ObservationIgnored private var operationInProgress = false
    @ObservationIgnored private var waitingOperations: [CheckedContinuation<Void, Never>] = []

    enum HabitLoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }
    private(set) var loadState: HabitLoadState = .idle
    
    // the habit data loaded into memory - in memory cache
    private var habitData = HabitData(enabledHabits: [], entries: [])

    // Observation dependency: `habitData`
    var enabledHabits: [Habit] {
        let availableIDs = Set(availableHabits.map(\.id))
        return habitData.enabledHabits.filter { availableIDs.contains($0.id) }
    }
    var availableHabits: [Habit] { Habit.availableHabits + habitData.customHabits }
    var activeHabits: [Habit] {
        let selected = Set(enabledHabits.map(\.id))
        return availableHabits.filter { selected.contains($0.id) }
    }

    func habit(for entry: HabitEntry) -> Habit {
        habitData.customHabits.first { $0.id == entry.habitID } ?? Habit(type: entry.habitType)
    }
    
    // Observation dependency: `habitData`
    var entries: [HabitEntry] { habitData.entries }

    // Observation dependency: `habitData`
    var weekSummaries: [String: HabitWeekSummary] { habitData.weekSummaries }
    // Observation dependency: `habitData`
    var lifetimeSummaries: [String: HabitLifetimeSummary] { habitData.lifetimeSummaries }

    private(set) var errorMessage: String?

    init(storage: any HabitDataStore, calendar: Calendar = .current,
         currentDate: @escaping @MainActor () -> Date) {
        worker = HabitsWorker(storage: storage, calendar: calendar)
        self.calendar = calendar
        self.currentDate = currentDate
    }

    func load() async {
        // Read saved habits once. Repeated callers share the load; a failed load can be retried.
        if let loadingTask {
            await loadingTask.value
            return
        }

        guard loadState != .ready else { return }
        let task = Task {
            defer { loadingTask = nil }
            await loadLocalData()
        }
        // The manager owns this request. Cancelling a caller does not cancel it for everyone.
        loadingTask = task
        await task.value
    }

    private func loadLocalData() async {
        await waitForPreviousOperation()
        defer { finishOperation() }
        let previousState = loadState
        if loadState != .ready { loadState = .loading }
        do {
            let today = currentDate()
            let result = try await worker.load(on: today)
            publishSuccessfulResult(result)
        } catch is CancellationError {
            loadState = previousState
        } catch {
            errorMessage = error.localizedDescription
            loadState = .failed(error.localizedDescription)
        }
    }
    
    func reload() async { await loadLocalData() }

    // Observation dependency: `habitData`
    func entry(for habitID: String, on date: Date) -> HabitEntry? {
        habitData.entriesByDay[habitID]?[calendar.startOfDay(for: date)]
    }

    // Observation dependency: `habitData`
    func todaysEntry(for habitID: String) -> HabitEntry? {
        habitData.todayEntries[habitID]
    }

    func weekSummary(for habitID: String, on date: Date) async -> HabitWeekSummary {
        await worker.weekSummary(entriesByDay: habitData.entriesByDay[habitID] ?? [:], on: date)
    }

    // Observation dependency: `habitData`
    func currentWeekSummary(for habitID: String) -> HabitWeekSummary {
        weekSummaries[habitID] ?? HabitWeekSummary(currentStreak: 0, days: [])
    }

    // Observation dependency: `habitData`
    func lifetimeSummary(for habitID: String) -> HabitLifetimeSummary {
        lifetimeSummaries[habitID] ?? HabitLifetimeSummary(totalValue: 0, firstEntryDate: nil)
    }

    // Called on foreground entry and calendar-day changes; no disk reload is needed.
    func updateCurrentDay() async {
        await waitForPreviousOperation()
        defer { finishOperation() }
        guard !Task.isCancelled, habitData.summaryDate != nil else { return }
        
        let today = currentDate()
        guard habitData.summaryDate != calendar.startOfDay(for: today) else { return }
        habitData = await worker.calculateSummaries(habitData, on: today)
    }

    private func publishSuccessfulResult(_ result: HabitData) {
        habitData = result
        errorMessage = nil
        loadState = .ready
    }

    private func waitForPreviousOperation() async {
        if operationInProgress {
            await withCheckedContinuation { waitingOperations.append($0) }
        } else {
            operationInProgress = true
        }
    }

    // Hand the turn to the next caller, keeping the flag true until the queue is empty.
    private func finishOperation() {
        if waitingOperations.isEmpty {
            operationInProgress = false
        } else {
            waitingOperations.removeFirst().resume()
        }
    }
}

// MARK: - Habit updates

extension HabitsFeature {
    @discardableResult
    func enableSelectedHabits(_ habitIDs: Set<String>, customNames: [String] = []) async throws -> [Habit] {
        await load()
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        guard loadState == .ready else { throw HabitError.notLoaded }
        
        let result = try await worker.selectHabits(habitIDs, habitData: habitData, today: currentDate(), customNames: customNames)
        publishSuccessfulResult(result)
        return enabledHabits
    }

    func recordDailyValue(_ value: Double, for habitID: String, distanceUnit: RunningDistanceUnit = .kilometres) async throws {
        await load()
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        guard loadState == .ready else { throw HabitError.notLoaded }
        let canonicalValue = habitID == Habit.HabitType.runningDistance.rawValue
            ? (distanceUnit.kilometres(from: value) * 10).rounded() / 10 : value
        let result = try await worker.recordDailyValue(canonicalValue, habitID: habitID, habitData: habitData, today: currentDate())
        publishSuccessfulResult(result)
    }

    @discardableResult
    func recordCoffee(on date: Date? = nil) async throws -> HabitEntry {
        let date = date ?? currentDate()
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        
        let result = try await worker.recordCoffee(on: date, habitData: habitData, today: currentDate())
        publishSuccessfulResult(result.habitData)
        return result.entry
    }

    @discardableResult
    func recordGymRepetitions(_ repetitions: Int, on date: Date? = nil) async throws -> HabitEntry {
        let date = date ?? currentDate()
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        
        let result = try await worker.recordGymRepetitions(repetitions, on: date, habitData: habitData, today: currentDate())
        publishSuccessfulResult(result.habitData)
        return result.entry
    }

    @discardableResult
    func recordRun(kilometres: Double, on date: Date? = nil) async throws -> HabitEntry {
        let date = date ?? currentDate()
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        
        let result = try await worker.recordRun(kilometres: kilometres, on: date, habitData: habitData, today: currentDate())
        publishSuccessfulResult(result.habitData)
        return result.entry
    }

    @discardableResult
    func recordSleep(hours: Double, on date: Date? = nil) async throws -> HabitEntry {
        let date = date ?? currentDate()
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        
        let result = try await worker.recordSleep(hours: hours, on: date, habitData: habitData, today: currentDate())
        publishSuccessfulResult(result.habitData)
        return result.entry
    }

    @discardableResult
    func recordWakeTime(minutesAfterMidnight: Int, on date: Date? = nil) async throws -> HabitEntry {
        let date = date ?? currentDate()
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        
        let result = try await worker.recordWakeTime(minutesAfterMidnight: minutesAfterMidnight, on: date, habitData: habitData, today: currentDate())
        publishSuccessfulResult(result.habitData)
        return result.entry
    }

    @discardableResult
    func recordGlassOfWater(on date: Date? = nil) async throws -> HabitEntry {
        let date = date ?? currentDate()
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        
        let result = try await worker.recordGlassOfWater(on: date, habitData: habitData, today: currentDate())
        publishSuccessfulResult(result.habitData)
        return result.entry
    }

    @discardableResult
    func recordAlcoholicDrink(on date: Date? = nil) async throws -> HabitEntry {
        let date = date ?? currentDate()
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        
        let result = try await worker.recordAlcoholicDrink(on: date, habitData: habitData, today: currentDate())
        publishSuccessfulResult(result.habitData)
        return result.entry
    }

    @discardableResult
    func removeCoffee(on date: Date? = nil) async throws -> HabitEntry? {
        let date = date ?? currentDate()
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        
        let result = try await worker.removeCoffee(on: date, habitData: habitData, today: currentDate())
        publishSuccessfulResult(result.habitData)
        return result.entry
    }

    func clearGymRepetitions(on date: Date? = nil) async throws {
        let date = date ?? currentDate()
        await waitForPreviousOperation()
        defer { finishOperation() }
        try Task.checkCancellation()
        
        let result = try await worker.clearGymRepetitions(on: date, habitData: habitData, today: currentDate())
        publishSuccessfulResult(result)
    }
}

enum HabitError: LocalizedError {
    case invalidValue
    case invalidHabitName
    case notLoaded

    var errorDescription: String? {
        switch self {
        case .invalidValue: "Enter a valid value before saving."
        case .invalidHabitName: "Give your habit a name between 1 and 60 characters."
        case .notLoaded: "Your habits haven’t loaded yet. Please try again."
        }
    }
}
