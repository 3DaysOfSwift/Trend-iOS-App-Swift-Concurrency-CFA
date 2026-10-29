// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class DailyHabitsViewModel {
    private let habitsFeature: HabitsFeature
    private let purchaseFeature: PurchaseFeature

    var drafts: [String: Double] = [:]
    var distanceUnit = RunningDistanceUnit.kilometres
    private(set) var savingIDs: Set<String> = []
    private(set) var feedback = 0
    var errorMessage: String?

    init(habitsFeature: HabitsFeature = AppModel.shared.habitsFeature,
         purchaseFeature: PurchaseFeature = AppModel.shared.purchaseFeature) {
        self.habitsFeature = habitsFeature
        self.purchaseFeature = purchaseFeature
    }

    var isUnlocked: Bool { purchaseFeature.hasUnlockedHabits }
    var habits: [Habit] { habitsFeature.activeHabits }
    var loadState: HabitsFeature.HabitLoadState { habitsFeature.loadState }
    var moods: [MorningMood] { MorningMood.allCases }

    func load() async {
        guard isUnlocked else { return }
        await habitsFeature.load()
    }

    func week(for habit: Habit) -> HabitWeekSummary { habitsFeature.currentWeekSummary(for: habit.id) }
    func value(for habit: Habit) -> Double? { habitsFeature.todaysEntry(for: habit.id)?.value }
    func draft(for habit: Habit) -> Double { drafts[habit.id] ?? habit.recordingPolicy.defaultValue }

    func description(for habit: Habit, value: Double?) -> String {
        guard let value else { return "Not recorded" }
        if habit.isDailyAnswer { return value == 1 ? "Yes" : "No" }
        if habit.type == .morningMood {
            return MorningMood(rawValue: Int(value)).map { "\($0.emoji) \($0.title)" } ?? "Recorded"
        }
        if habit.type == .wakeTime { return String(format: "%02d:%02d", Int(value) / 60, Int(value) % 60) }
        if habit.type == .runningDistance {
            return "\(distanceUnit.value(fromKilometres: value).formatted(.number.precision(.fractionLength(0...1)))) \(distanceUnit == .miles ? "mi" : "km")"
        }
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(habit.unit)"
    }

    func record(_ habit: Habit, value: Double) async {
        guard isUnlocked, savingIDs.insert(habit.id).inserted else { return }
        defer { savingIDs.remove(habit.id) }
        do {
            try await habitsFeature.recordDailyValue(value, for: habit.id, distanceUnit: distanceUnit)
            errorMessage = nil
            feedback += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() { errorMessage = nil }
}
