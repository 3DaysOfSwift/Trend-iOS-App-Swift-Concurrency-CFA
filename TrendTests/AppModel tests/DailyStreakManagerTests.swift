// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DailyStreakManagerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func sevenDayBarShowsPositiveAndAttentionResults() async {
        let entries = [
            WeightEntry(date: date(day: 5), kilograms: 80),
            WeightEntry(date: date(day: 6), kilograms: 79),
            WeightEntry(date: date(day: 7), kilograms: 79.5)
        ]
        let manager = makeManager()

        await manager.refresh(entries: entries, now: date(day: 7, hour: 12))

        #expect(manager.snapshot.days.count == 7)
        #expect(manager.snapshot.days.prefix(3).map(\.result) == [
            .positive,
            .positive,
            .needsAttention
        ])
        #expect(manager.snapshot.currentStreak == 3)
    }

    @Test func streakRemainsAliveBeforeTodaysCheckIn() async {
        let entries = [
            WeightEntry(date: date(day: 5), kilograms: 80),
            WeightEntry(date: date(day: 6), kilograms: 79.8)
        ]
        let manager = makeManager()

        await manager.refresh(entries: entries, now: date(day: 7, hour: 12))

        #expect(manager.snapshot.currentStreak == 2)
        let today = manager.snapshot.days.first(where: \.isToday)
        #expect(today?.result == .noCheckIn)
    }

    @Test func missedPreviousDayBreaksTheStreak() async {
        let manager = makeManager()
        await manager.refresh(
            entries: [WeightEntry(date: date(day: 5), kilograms: 80)],
            now: date(day: 7, hour: 12)
        )

        #expect(manager.snapshot.currentStreak == 0)
    }

    @Test func olderRefreshCannotReplaceNewerEmptySnapshot() async {
        let assessor = PausedTrendAssessor()
        let manager = DailyStreakManager(trend: assessor, calendar: calendar,
            currentDate: TestAppModelFactory.currentDate)
        let now = date(day: 7, hour: 12)
        let entries = [WeightEntry(date: date(day: 7), kilograms: 80)]
        let older = Task { await manager.refresh(entries: entries, now: now) }
        await assessor.waitForAssessment()

        await manager.refresh(entries: [], now: now)
        let newerSnapshot = manager.snapshot
        #expect(newerSnapshot.currentStreak == 0)
        #expect(newerSnapshot.days.allSatisfy { $0.result == .noCheckIn })

        await assessor.completeAssessment()
        await older.value
        #expect(manager.snapshot == newerSnapshot)
    }

    private func makeManager() -> DailyStreakManager {
        DailyStreakManager(
            trend: DailyTrendManager(calendar: calendar),
            calendar: calendar,
            currentDate: TestAppModelFactory.currentDate
        )
    }

    private func date(day: Int, hour: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }
}


private actor PausedTrendAssessor: DailyTrendAssessing {
    private var release: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func assess(entries: [WeightEntry], newestEntryID: UUID) async -> DailyTrendAssessment {
        await withCheckedContinuation { continuation in
            release = continuation
            started?.resume()
            started = nil
        }
        return DailyTrendAssessment(verdict: .positive, title: "Check-in complete",
            message: "Assessment completed", changeKilograms: nil)
    }

    func waitForAssessment() async {
        if release != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func completeAssessment() {
        release?.resume()
        release = nil
    }
}
