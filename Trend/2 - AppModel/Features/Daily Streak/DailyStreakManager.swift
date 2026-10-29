// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

struct DailyStreakSnapshot: Sendable, Equatable {
    struct Day: Identifiable, Sendable, Equatable {
        enum Result: Sendable, Equatable {
            case positive
            case needsAttention
            case noCheckIn
        }

        var id: Date { date }
        let date: Date
        let result: Result
        let isToday: Bool
    }

    let currentStreak: Int
    let days: [Day]

    static let empty = DailyStreakSnapshot(currentStreak: 0, days: [])
}

@MainActor
@Observable
final class DailyStreakManager {
    @ObservationIgnored private var latestRefreshID: UUID?
    private let trend: any DailyTrendAssessing
    private let calendar: Calendar
    private let currentDate: @MainActor () -> Date

    private(set) var snapshot: DailyStreakSnapshot = .empty

    init(trend: any DailyTrendAssessing, calendar: Calendar = .current, currentDate: @escaping @MainActor () -> Date) {
        self.trend = trend
        self.calendar = calendar
        self.currentDate = currentDate
    }

    func refresh(entries: [WeightEntry], now: Date? = nil) async {
        let refreshID = UUID()
        latestRefreshID = refreshID
        let now = now ?? currentDate()
        let today = calendar.startOfDay(for: now)
        let entriesByDay = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.date)
        }
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let dates = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: monday)
        }

        var days: [DailyStreakSnapshot.Day] = []
        for date in dates {
            guard let entry = entriesByDay[date]?.max(by: { $0.date < $1.date }) else {
                days.append(.init(date: date, result: .noCheckIn, isToday: date == today))
                continue
            }

            let assessment = await trend.assess(entries: entries, newestEntryID: entry.id)
            // A later refresh may have published while this calculation was suspended.
            guard latestRefreshID == refreshID else { return }
            days.append(.init(
                date: date,
                result: assessment.verdict == .positive ? .positive : .needsAttention,
                isToday: date == today
            ))
        }

        snapshot = DailyStreakSnapshot(
            currentStreak: currentStreak(entriesByDay: entriesByDay, today: today),
            days: days
        )
    }

    private func currentStreak(
        entriesByDay: [Date: [WeightEntry]],
        today: Date
    ) -> Int {
        var cursor = today

        // A streak remains alive until the current day has finished. Before today's
        // check-in, count backward from yesterday just as a daily habit app does.
        if entriesByDay[cursor] == nil {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while entriesByDay[cursor] != nil {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
