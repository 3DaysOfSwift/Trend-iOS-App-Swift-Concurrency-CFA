// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct DailyTipsFeatureTests {
    @Test func catalogContainsExactlyOneHundredTips() {
        let manager = makeManager()
        #expect(manager.catalogCount == 100)
        #expect(manager.pepTalkCatalogCount == 100)
        #expect(manager.poisonPointCatalogCount == 100)
        #expect(manager.evolutionCatalogCount == 100)
        #expect(manager.fastingCatalogCount == 10)
    }

    @Test func fastingSuggestionAppearsEveryTenthRefresh() {
        let manager = makeManager()

        for _ in 1...9 {
            manager.refresh()
            #expect(manager.currentFastingSuggestion == nil)
        }

        manager.refresh()
        let firstSuggestion = manager.currentFastingSuggestion
        #expect(firstSuggestion != nil)

        for _ in 11...19 {
            manager.refresh()
            #expect(manager.currentFastingSuggestion == nil)
        }

        manager.refresh()
        #expect(manager.currentFastingSuggestion != nil)
        #expect(manager.currentFastingSuggestion?.id != firstSuggestion?.id)
    }

    @Test func everyTipIsUsedBeforeTheQueueRefills() {
        let manager = makeManager()
        let firstCycle = (0..<100).map { _ in manager.nextTip() }

        #expect(Set(firstCycle.map(\.id)).count == 100)
        #expect(manager.remainingCount == 0)

        let nextCycleTip = manager.nextTip()
        #expect((1...100).contains(nextCycleTip.id))
        #expect(manager.remainingCount == 99)
    }

    @Test func additionalDecksCycleIndependentlyWithoutRepeating() {
        let manager = makeManager()

        let pepTalks = (0..<100).map { _ in manager.nextPepTalk() }
        let poisonPoints = (0..<100).map { _ in manager.nextPoisonPoint() }
        let evolutionPoints = (0..<100).map { _ in manager.nextEvolutionPoint() }

        #expect(Set(pepTalks.map(\.text)).count == 100)
        #expect(Set(poisonPoints.map(\.text)).count == 100)
        #expect(Set(evolutionPoints.map(\.text)).count == 100)
        #expect(manager.remainingPepTalkCount == 0)
        #expect(manager.remainingPoisonPointCount == 0)
        #expect(manager.remainingEvolutionPointCount == 0)

        _ = manager.nextPepTalk()
        #expect(manager.remainingPepTalkCount == 99)
        #expect(manager.remainingPoisonPointCount == 0)
        #expect(manager.remainingEvolutionPointCount == 0)
    }

    @Test func whatNextIsScheduledByTheFeatureForMondayOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let manager = makeManager(calendar: calendar)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!

        #expect(manager.whatNext(on: monday) == .standard)
        #expect(manager.whatNext(on: tuesday) == nil)
    }

    private func makeManager(calendar: Calendar = .current) -> DailyTipsFeature {
        DailyTipsFeature(defaults: makeDefaults(), calendar: calendar, currentDate: TestAppModelFactory.currentDate)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "DailyTipsFeatureTests.\(UUID().uuidString)")!
    }
}
