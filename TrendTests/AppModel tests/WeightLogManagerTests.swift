// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WeightLogManagerTests {
    @Test func addingEntryPersistsCanonicalKilograms() async throws {
        let repository = InMemoryWeightRepository()
        let manager = WeightLogManager(repository: repository)
        await manager.load()
        try await manager.add(
            WeightEntryDraft(date: .now, value: "75.5", note: " Test "),
            unit: .kilograms
        )
        let stored = try await repository.load()
        #expect(stored.entries.first?.kilograms == 75.5)
        #expect(stored.entries.first?.note == "Test")
    }

    @Test func overlappingSavesRetainEveryEntry() async throws {
        let repository = InMemoryWeightRepository()
        let manager = WeightLogManager(repository: repository)
        let tasks = (0..<20).map { index in
            Task { @MainActor in
                try await manager.add(WeightEntryDraft(date: .now, value: "\(70 + index)"), unit: .kilograms)
            }
        }
        for task in tasks { try await task.value }
        #expect(manager.entries.count == 20)
        #expect(try await repository.load().entries.count == 20)
    }

    @Test func successfulSavePublishesEvenIfCallerCancelsDuringPersistence() async throws {
        let repository = PausedWeightRepository()
        let manager = WeightLogManager(repository: repository)
        await manager.load()
        let saving = Task {
            try await manager.add(WeightEntryDraft(date: .now, value: "75"), unit: .kilograms)
        }
        await repository.waitForSave()
        #expect(manager.entries.isEmpty)
        saving.cancel()
        await repository.finishSave()
        try await saving.value
        #expect(manager.entries.count == 1)
        #expect(await repository.load().entries == manager.entries)
    }

    @Test func failedSaveLeavesStateIntactAndReleasesOperationGate() async throws {
        let repository = PausedWeightRepository()
        let manager = WeightLogManager(repository: repository)
        await manager.load()
        let saving = Task {
            try await manager.add(WeightEntryDraft(date: .now, value: "75"), unit: .kilograms)
        }
        await repository.waitForSave()
        await repository.finishSave(failing: true)
        do {
            try await saving.value
            Issue.record("The repository failure must reach the caller")
        } catch {
            #expect((error as? CocoaError)?.code == .fileWriteUnknown)
        }
        #expect(manager.entries.isEmpty)
        #expect(await repository.load().entries.isEmpty)
        try await manager.add(WeightEntryDraft(date: .now, value: "76"), unit: .kilograms)
        #expect(manager.entries.map(\.kilograms) == [76])
        #expect(await repository.load().entries == manager.entries)
    }

}


/// Pauses the first write at the persistence boundary; later writes complete normally.
private actor PausedWeightRepository: WeightRepository {
    private var store = WeightStore(entries: [], goalKilograms: nil)
    private var shouldPause = true
    private var saveRelease: CheckedContinuation<Bool, Never>?
    private var saveStarted: CheckedContinuation<Void, Never>?

    func load() -> WeightStore { store }

    func save(_ candidate: WeightStore) async throws {
        if shouldPause {
            shouldPause = false
            let failing = await withCheckedContinuation { continuation in
                saveRelease = continuation
                saveStarted?.resume()
                saveStarted = nil
            }
            if failing { throw CocoaError(.fileWriteUnknown) }
        }
        store = candidate
    }

    func waitForSave() async {
        if saveRelease != nil { return }
        await withCheckedContinuation { saveStarted = $0 }
    }

    func finishSave(failing: Bool = false) {
        saveRelease?.resume(returning: failing)
        saveRelease = nil
    }
}
