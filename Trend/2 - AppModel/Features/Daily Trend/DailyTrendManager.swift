// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation

struct DailyTrendAssessment: Sendable, Equatable {
    enum Verdict: Sendable, Equatable {
        case positive
        case needsAttention
    }

    let verdict: Verdict
    let title: String
    let message: String
    let changeKilograms: Double?
}
        
struct DailyCheckInResult: Sendable, Equatable {
    let assessment: DailyTrendAssessment
    let tip: WellnessTip
    let pepTalk: WellnessTip
    let poisonPoint: WellnessTip
    let evolutionPoint: WellnessTip
    let fastingPoint: WellnessTip?
    let whatNext: WhatNextGuidance?
}

protocol DailyTrendAssessing: Sendable {
    func assess(entries: [WeightEntry], newestEntryID: UUID) async -> DailyTrendAssessment
}

actor DailyTrendManager: DailyTrendAssessing {
    private let stableToleranceKilograms: Double
    private let plateauLimitDays: Int
    private let calendar: Calendar

    init(
        stableToleranceKilograms: Double = 0.2,
        plateauLimitDays: Int = 5,
        calendar: Calendar = .current
    ) {
        self.stableToleranceKilograms = stableToleranceKilograms
        self.plateauLimitDays = plateauLimitDays
        self.calendar = calendar
    }

    func assess(entries: [WeightEntry], newestEntryID: UUID) -> DailyTrendAssessment {
        let ordered = entries.sorted { $0.date < $1.date }
        guard
            let newestIndex = ordered.firstIndex(where: { $0.id == newestEntryID }),
            newestIndex > ordered.startIndex
        else {
            return DailyTrendAssessment(
                verdict: .positive,
                title: "Check-in complete",
                message: "Your trend begins with this measurement.",
                changeKilograms: nil
            )
        }

        let newest = ordered[newestIndex]
        let previous = ordered[ordered.index(before: newestIndex)]
        let change = newest.kilograms - previous.kilograms

        if change < -stableToleranceKilograms {
            return DailyTrendAssessment(
                verdict: .positive,
                title: "Moving downward",
                message: "Your latest check-in is lower than the one before it.",
                changeKilograms: change
            )
        }

        if change > stableToleranceKilograms {
            return DailyTrendAssessment(
                verdict: .needsAttention,
                title: "Trend moved upward",
                message: "One reading is only data. Use it to make your next small choice.",
                changeKilograms: change
            )
        }

        let historyThroughNewest = Array(ordered[...newestIndex])
        let lastLossDate = zip(historyThroughNewest, historyThroughNewest.dropFirst())
            .reversed()
            .first { older, newer in
                newer.kilograms < older.kilograms - stableToleranceKilograms
            }?
            .1.date
        let plateauStart = lastLossDate ?? historyThroughNewest.first?.date ?? newest.date
        let plateauDays = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: plateauStart),
            to: calendar.startOfDay(for: newest.date)
        ).day ?? 0

        if plateauDays > plateauLimitDays {
            return DailyTrendAssessment(
                verdict: .needsAttention,
                title: "Time for a reset",
                message: "Your trend has stayed level for more than five days. Try one manageable change today.",
                changeKilograms: change
            )
        }

        return DailyTrendAssessment(
            verdict: .positive,
            title: "Holding steady",
            message: "Consistency counts. Your trend remains stable today.",
            changeKilograms: change
        )
    }
}
