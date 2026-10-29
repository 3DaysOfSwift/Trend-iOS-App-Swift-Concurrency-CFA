// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
final class HabitHistoryViewModel {
    private let habitsFeature: HabitsFeature

    init(habitsFeature: HabitsFeature = AppModel.shared.habitsFeature) {
        self.habitsFeature = habitsFeature
    }

    var entries: [HabitEntry] { habitsFeature.entries }

    func habit(for entry: HabitEntry) -> Habit {
        habitsFeature.habit(for: entry)
    }

    func valueDescription(for entry: HabitEntry) -> String {
        let habit = habit(for: entry)
        if habit.isDailyAnswer { return entry.value == 1 ? "Yes" : "No" }
        switch habit.valueType {
        case .timeOfDay:
            let hour = Int(entry.value) / 60
            let minute = Int(entry.value) % 60
            let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: entry.date) ?? entry.date
            return date.formatted(date: .omitted, time: .shortened)
        case .rating:
            return MorningMood(rawValue: Int(entry.value)).map { "\($0.emoji) \($0.title)" } ?? "Recorded"
        case .number:
            let value = entry.value.formatted(.number.precision(.fractionLength(0...1)))
            return "\(value) \(habit.unit)"
        }
    }
}
