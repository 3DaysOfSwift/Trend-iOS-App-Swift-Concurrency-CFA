import Foundation
import Testing
@testable import Trend

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WeightEntryFeatureTests {
    @Test func overlappingCheckInsAssessTheirOwnInsertedEntry() async throws {
        let repository = CheckInRepository()
        let feature = TestAppModelFactory.make(repository: repository).weightEntryFeature
        await feature.refresh()
        let first = Task {
            try await feature.checkIn(.init(date: Date(timeIntervalSince1970: 200), value: "75"))
        }
        await repository.waitForSave()
        var second: Task<DailyTrendAssessment, Error>?
        await withCheckedContinuation { started in
            second = Task {
                started.resume()
                return try await feature.checkIn(.init(date: Date(timeIntervalSince1970: 100), value: "78"))
            }
        }
        await repository.finishSave()
        _ = try await first.value
        let secondTask = try #require(second)
        let assessment = try await secondTask.value
        #expect(assessment.changeKilograms == -2)
        #expect(feature.entries.count == 3)
        #expect(await repository.load().entries.count == 3)
    }
}

private actor CheckInRepository: WeightRepository, CloudSyncStatusProviding {
    private var store = WeightStore(entries: [WeightEntry(date: Date(timeIntervalSince1970: 0), kilograms: 80)], goalKilograms: nil)
    private var shouldPause = true
    private var release: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func cloudStatus() -> CloudSyncStatus { .unavailable }
    func load() -> WeightStore { store }
    func save(_ candidate: WeightStore) async throws {
        if shouldPause {
            shouldPause = false
            await withCheckedContinuation { continuation in
                release = continuation
                started?.resume()
                started = nil
            }
        }
        store = candidate
    }
    func waitForSave() async {
        if release != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finishSave() { release?.resume(); release = nil }
}
