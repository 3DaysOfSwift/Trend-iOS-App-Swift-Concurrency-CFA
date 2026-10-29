// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct LocalPersistenceTests {
    @Test func unchangedSnapshotHasStableIdentity() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = LocalDataStore(directory: folder)
        try await storage.saveWeight(WeightStore(entries: [WeightEntry(date: .now, kilograms: 70)], goalKilograms: nil))
        let first = try await storage.snapshot()
        #expect(try await storage.snapshot().revision == first.revision)
        _ = try await storage.saveHabitPreferences(selected: [Habit(type: .water)], custom: [])
        #expect(try await storage.snapshot().revision != first.revision)
        await storage.close()
    }

    @Test func staleWeightSavePreservesUnseenRecordsAndRemoteEdits() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = LocalDataStore(directory: folder)
        let original = WeightEntry(date: .now, kilograms: 70)
        try await first.saveWeight(WeightStore(entries: [original], goalKilograms: nil))
        _ = try await first.loadWeight()
        // A second local context simulates changes arriving from elsewhere.
        // This tests delta application, not the CloudKit network transport.
        let second = LocalDataStore(directory: folder)
        _ = try await second.loadWeight()
        let edited = WeightEntry(id: original.id, date: original.date, kilograms: 71)
        let unseen = WeightEntry(date: .now, kilograms: 69)
        try await second.saveWeight(WeightStore(entries: [edited, unseen], goalKilograms: nil))
        let added = WeightEntry(date: .now, kilograms: 68)
        try await first.saveWeight(WeightStore(entries: [original, added], goalKilograms: nil))
        let result = try await first.loadWeight()
        #expect(Set(result.entries.map(\.id)) == Set([original.id, unseen.id, added.id]))
        #expect(result.entries.first { $0.id == original.id }?.kilograms == 71)
        await first.close()
        await second.close()
    }

    @Test func staleHabitSavePreservesUnseenEntries() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = LocalDataStore(directory: folder)
        _ = try await first.loadHabits()
        let second = LocalDataStore(directory: folder)
        let unseen = HabitEntry(id: UUID(), habitType: .water, date: .now, value: 3)
        _ = try await second.saveHabitEntries([unseen])
        let added = HabitEntry(id: UUID(), habitType: .morningMood, date: .now, value: 4)
        _ = try await first.saveHabitEntries([added])
        #expect(try await first.loadHabits().entries.count == 2)
        await first.close()
        await second.close()
    }
    @Test func recordsAndSelectionsSurviveClosingAndReopeningDatabase() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let date = Date(timeIntervalSince1970: 1_788_480_000)
        let storage = LocalDataStore(directory: folder)
        let weight = WeightLogManager(repository: LocalWeightRepository(storage: storage))
        try await weight.add(WeightEntryDraft(date: date, value: "69.7"), unit: .kilograms)
        let habits = HabitsFeature(storage: LocalHabitRepository(storage: storage), currentDate: { date })
        try await habits.enableSelectedHabits(["morningMood", "water"])
        try await habits.recordDailyValue(4, for: "morningMood")
        await storage.close()

        let reopened = LocalDataStore(directory: folder)
        let restoredWeight = try await reopened.loadWeight()
        let restoredHabits = try await reopened.loadHabits()
        #expect(restoredWeight.entries.count == 1)
        #expect(restoredWeight.entries.first?.kilograms == 69.7)
        #expect(Set(restoredHabits.enabledHabits.map(\.id)) == ["morningMood", "water"])
        #expect(restoredHabits.entries.first?.value == 4)
        await reopened.close()
    }

    @Test func recordingEntriesCannotWriteHabitPreferences() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = LocalDataStore(directory: folder)
        let repository = LocalHabitRepository(storage: storage)
        _ = try await repository.savePreferences(selected: [Habit(type: .water)], custom: [])
        let entry = HabitEntry(id: UUID(), habitType: .water, date: .now, value: 1)
        _ = try await repository.saveEntries([entry])
        #expect(try await repository.load().enabledHabits.map(\.id) == ["water"])
        _ = try await repository.savePreferences(selected: [], custom: [])
        #expect(try await repository.load().entries == [entry])
        await storage.close()
    }

    @Test func failedTransactionLeavesPreviousEntriesIntact() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = LocalDataStore(directory: folder)
        let good = WeightEntry(date: .now, kilograms: 70)
        try await storage.saveWeight(WeightStore(entries: [good], goalKilograms: nil))
        await #expect(throws: (any Error).self) {
            try await storage.saveWeight(WeightStore(entries: [WeightEntry(date: .now, kilograms: .infinity)], goalKilograms: nil))
        }
        #expect(try await storage.loadWeight().entries == [good])
        await storage.close()
    }

    @Test func restoreIsExplicitTransactionalAndPreservesRecoveryCopy() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = LocalDataStore(directory: folder)
        let first = WeightEntry(date: .now, kilograms: 70)
        try await storage.saveWeight(WeightStore(entries: [first], goalKilograms: nil))
        let backup = try await storage.snapshot()
        try await storage.saveWeight(WeightStore(entries: [], goalKilograms: nil))
        #expect(try await storage.loadWeight().entries.isEmpty)
        try await storage.restore(backup)
        #expect(try await storage.loadWeight().entries == [first])
        await #expect(throws: (any Error).self) { try await storage.saveWeight(WeightStore(entries: [], goalKilograms: nil)) }
        await storage.finishRestore()
        let copies = try FileManager.default.contentsOfDirectory(at: folder.appending(path: "Backups/Before-restore"), includingPropertiesForKeys: nil)
        #expect(copies.count == 1)
        let previous = try JSONDecoder().decode(RecoverySnapshot.self, from: Data(contentsOf: copies[0]))
        #expect(previous.weight.entries.isEmpty)
        await storage.close()
    }

    @Test func invalidBackupDoesNotReplaceRecords() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = LocalDataStore(directory: folder)
        let entry = WeightEntry(date: .now, kilograms: 70)
        try await storage.saveWeight(WeightStore(entries: [entry], goalKilograms: nil))
        var backup = try await storage.snapshot()
        backup.formatVersion = 99
        await #expect(throws: (any Error).self) { try await storage.restore(backup) }
        #expect(try await storage.loadWeight().entries == [entry])
        await storage.close()
    }


}
