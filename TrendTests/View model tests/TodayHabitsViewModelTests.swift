// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct TodayHabitsViewModelTests {
    @Test func lockedTodayCannotRecordAPaidHabit() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { .now })
        try await manager.enableSelectedHabits(["yoga"])
        let model = TodayHabitsViewModel(habitsFeature: manager, purchaseFeature: PurchaseFeature(client: InMemoryPurchaseClient()))
        await model.record(Habit(type: .yoga), value: 1)
        #expect(!model.isUnlocked)
        #expect(manager.entries.isEmpty)
    }

    @Test func unlockedTodayRecordsAndExposesSharedValues() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { .now })
        try await manager.enableSelectedHabits(["yoga"])
        let purchase = PurchaseFeature(client: InMemoryPurchaseClient())
        await purchase.purchaseHabits()
        let model = TodayHabitsViewModel(habitsFeature: manager, purchaseFeature: purchase)
        let otherScreen = DailyHabitsViewModel(habitsFeature: manager, purchaseFeature: purchase)
        await model.record(Habit(type: .yoga), value: 1)
        #expect(model.feedback == 1)
        #expect(model.savingIDs.isEmpty)
        #expect(otherScreen.value(for: Habit(type: .yoga)) == 1)
    }

    @Test func failedValidationPreservesDraftAndDoesNotCelebrate() async throws {
        let manager = HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { .now })
        try await manager.enableSelectedHabits(["sauna"])
        let purchase = PurchaseFeature(client: InMemoryPurchaseClient())
        await purchase.purchaseHabits()
        let model = TodayHabitsViewModel(habitsFeature: manager, purchaseFeature: purchase)
        model.drafts["sauna"] = -3
        await model.record(Habit(type: .sauna), value: -3)
        #expect(model.drafts["sauna"] == -3)
        #expect(model.errorMessage != nil)
        #expect(model.feedback == 0)
        #expect(model.savingIDs.isEmpty)
    }

    @Test func labelsDistinguishMissingNoAndMood() {
        let model = TodayHabitsViewModel(habitsFeature: HabitsFeature(storage: InMemoryHabitDataStore(), currentDate: { .now }), purchaseFeature: PurchaseFeature(client: InMemoryPurchaseClient()))
        #expect(model.description(for: Habit(type: .sauna), value: nil) == "Not recorded")
        #expect(model.description(for: Habit(type: .sauna), value: 0) == "No")
        #expect(model.description(for: Habit(type: .morningMood), value: 5) == "🤩 Energetic")
    }
}
