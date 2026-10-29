// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Observation

@MainActor @Observable
final class TodayActivityHabitsViewModel {
    private let feature: HabitsFeature
    var showsRunEntry = false
    var errorMessage: String?
    private(set) var savingIDs: Set<String> = []

    init(feature: HabitsFeature = AppModel.shared.habitsFeature) { self.feature = feature }

    var habits: [Habit] { feature.activeHabits.filter { $0.isDailyAnswer || $0.type == .runningDistance } }
    func isSelected(_ habit: Habit) -> Bool { (feature.todaysEntry(for: habit.id)?.value ?? 0) > 0 }
    func emoji(_ habit: Habit) -> String {
        switch habit.type {
        case .yoga: "🧘"
        case .meditation: "🪷"
        case .gymAttendance: "🏋️"
        case .sauna: "🧖"
        case .runningDistance: "🏃"
        default: "✅"
        }
    }

    func select(_ habit: Habit) async {
        if habit.type == .runningDistance {
            showsRunEntry = true
            return
        }
        guard savingIDs.insert(habit.id).inserted else { return }
        defer { savingIDs.remove(habit.id) }
        do {
            try await feature.recordDailyValue(isSelected(habit) ? 0 : 1, for: habit.id)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func dismissError() { errorMessage = nil }
}
