// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

struct WeightImportTests {
    private let zone = TimeZone(secondsFromGMT: 0)!

    @Test func diaryPreservesPrecisionAndIgnoresProfileFields() async throws {
        let text = """
        units,kg
        goal,70
        height,175
        birthdate,1983-12-20
        gender,M
        2026-09-13 13:33:39,70.8000,20.2
        2014-06-30 06:00:00,77.1107
        """
        let result = try await WeightImportFileReader().decode(Data(text.utf8), timeZone: zone)
        #expect(result.source == "Weight Diary CSV")
        #expect(result.entries.count == 2)
        #expect(result.entries.last?.kilograms == 77.1107)
        #expect(result.entries.first?.note == "")
    }

    @Test func genericCSVSupportsPoundsQuotedNotesBOMAndCRLF() async throws {
        let text = "\u{feff}date,weight,unit,note\r\n2026-09-13T12:00:00Z,154.3235835,lb,\"Gym, then a \"\"walk\"\"\nHome\"\r\n"
        let result = try await WeightImportFileReader().decode(Data(text.utf8), timeZone: zone)
        #expect(abs(result.entries[0].kilograms - 70) < 0.000001)
        #expect(result.entries[0].note == "Gym, then a \"walk\"\nHome")
    }

    @Test func malformedRowsAndUnsupportedUnitsRejectTheEntireFile() async {
        for text in [
            "units,stones\n2026-09-13 12:00:00,11",
            "units,kg\n2026-09-13 12:00:00,70\nnot-a-date,71",
            "units,kg\n2026-02-30 12:00:00,70",
            "units,kg\n2026-09-13 12:00:00,nan",
            "units,kg\n2026-09-13 12:00:00,-70",
            "date,weight,unit,note\n2026-09-13,70,kg,\"unfinished",
            "date,weight,unit\n09/10/2026,70,kg",
            ""
        ] {
            await #expect(throws: (any Error).self) {
                try await WeightImportFileReader().decode(Data(text.utf8), timeZone: zone)
            }
        }
    }

    @Test func JSONWeightExportAndVersionedRecoveryBackupAreSupported() async throws {
        let entry = WeightEntry(date: Date(timeIntervalSince1970: 1_700_000_000), kilograms: 69.7, note: "Keep me")
        let store = WeightStore(entries: [entry], goalKilograms: 60)
        let data = try await BackupFileManager().encode(store)
        let result = try await WeightImportFileReader().decode(data, timeZone: zone)
        #expect(result.entries == [entry])
        let snapshot = RecoverySnapshot(revision: UUID().uuidString, createdAt: entry.date,
                                        weight: store, habits: HabitData(enabledHabits: [], entries: []))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let backup = try await WeightImportFileReader().decode(encoder.encode(snapshot), timeZone: zone)
        #expect(backup.source == "Trend recovery backup")
        #expect(backup.entries == [entry])
        var unsupported = snapshot
        unsupported.formatVersion = 999
        await #expect(throws: (any Error).self) {
            try await WeightImportFileReader().decode(encoder.encode(unsupported), timeZone: zone)
        }
    }

    @MainActor @Test func repeatedAndConcurrentImportsAreAdditiveAndPreserveGoal() async throws {
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = WeightEntry(date: time, kilograms: 70, note: "My existing note")
        let other = WeightEntry(date: time.addingTimeInterval(3600), kilograms: 70)
        let repository = InMemoryWeightRepository(store: WeightStore(entries: [existing], goalKilograms: 60))
        let manager = WeightLogManager(repository: repository)
        let duplicate = WeightEntry(date: time, kilograms: 70, note: "Do not replace my note")
        async let a = manager.mergeImportedEntries([duplicate, other])
        async let b = manager.mergeImportedEntries([duplicate, other])
        let results = try await [a, b]
        #expect(results.map { $0.additions.count }.reduce(0, +) == 1)
        #expect(manager.entries.count == 2)
        #expect(manager.entries.first(where: { $0.id == existing.id })?.note == existing.note)
        #expect(manager.goalKilograms == 60)
        #expect(await repository.saveCallCount == 1)
        let reloaded = WeightLogManager(repository: repository)
        await reloaded.load()
        #expect(reloaded.entries == manager.entries)
    }

    @MainActor @Test func saveFailureLeavesExistingDataIntact() async throws {
        let existing = WeightEntry(date: .now, kilograms: 70)
        let repository = InMemoryWeightRepository(store: .init(entries: [existing], goalKilograms: 60), saveError: .saveFailed)
        let manager = WeightLogManager(repository: repository)
        await manager.load()
        await #expect(throws: (any Error).self) {
            try await manager.mergeImportedEntries([WeightEntry(date: .now, kilograms: 69)])
        }
        #expect(manager.entries == [existing])
        #expect(try await repository.load().entries == [existing])
    }

    @MainActor @Test func previewDoesNotWriteAndConfirmationWritesOnce() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try Data("units,kg\n2026-09-13 12:00:00,70".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = InMemoryWeightRepository()
        let manager = WeightLogManager(repository: repository)
        let feature = WeightImportFeature(weightLog: manager, refresh: {})
        let viewModel = WeightImportViewModel(url: url, feature: feature)
        await viewModel.load()
        #expect(viewModel.canImport)
        #expect(viewModel.count == 1)
        #expect(await repository.saveCallCount == 0)
        await viewModel.importEntries()
        await viewModel.importEntries()
        #expect(viewModel.result?.additions.count == 1)
        #expect(await repository.saveCallCount == 1)
    }

    @Test func inspectProvidedSampleWhenRequested() async throws {
        // The user's health history stays outside the repository and fixtures.
        guard let path = ProcessInfo.processInfo.environment["TREND_IMPORT_SAMPLE_PATH"] else { return }
        let document = try await WeightImportFileReader().read(URL(fileURLWithPath: path), timeZone: zone)
        #expect(document.entries.count == 706)
        #expect(document.entries.first?.kilograms == 70.8)
        #expect(document.entries.last?.kilograms == 77.1107)
    }

    @MainActor @Test func importedRecordsSurviveReopeningSwiftDataWithoutChangingHabits() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = LocalDataStore(directory: directory)
        let habit = Habit(type: .water)
        _ = try await storage.saveHabitPreferences(selected: [habit], custom: [])
        let manager = WeightLogManager(repository: LocalWeightRepository(storage: storage))
        let entry = WeightEntry(date: Date(timeIntervalSince1970: 1_700_000_000), kilograms: 69.7123)
        _ = try await manager.mergeImportedEntries([entry])
        let reopened = LocalDataStore(directory: directory)
        #expect(try await reopened.loadWeight().entries == [entry])
        #expect(try await reopened.loadHabits().enabledHabits == [habit])
    }
}
