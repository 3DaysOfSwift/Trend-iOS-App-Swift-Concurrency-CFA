// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Testing
@testable import Trend

@MainActor
struct AppModelTests {
    @Test func launchRegistersPurchasesImmediatelyAndStartsLoadsOnlyOnce() async {
        let repository = StartupProbeRepository()
        let client = InMemoryPurchaseClient()
        let appModel = TestAppModelFactory.make(repository: repository, purchaseClient: client)
        appModel.applicationDidFinishLaunching()
        #expect(client.observationCount == 1)
        appModel.applicationDidFinishLaunching()
        #expect(client.observationCount == 1)

        for _ in 0..<1000 {
            if await repository.didStartBothOperations { break }
            await Task.yield()
        }
        #expect(await repository.didStartBothOperations)
        #expect(await repository.loadCallCount == 1)
        #expect(await repository.cloudStatusCallCount == 1)
        await repository.releaseOperations()
    }

    @Test func goalWorkflowOwnsValidationAndUnitConversion() async throws {
        let repository = InMemoryWeightRepository()
        let appModel = TestAppModelFactory.make(repository: repository, unit: .pounds)

        #expect(!appModel.settingsFeature.canSetGoal(from: "10"))
        #expect(appModel.settingsFeature.canSetGoal(from: "154.3"))

        try await appModel.settingsFeature.setGoal(from: "154.3")

        #expect(abs((appModel.settingsFeature.goalWeightKilograms ?? 0) - 69.989) < 0.01)
    }

    @Test func settingsCommandsRemainBehindAppModelBoundary() async {
        let repository = InMemoryWeightRepository(cloudStatus: .available)
        let appModel = TestAppModelFactory.make(repository: repository)

        appModel.settingsFeature.setWeightUnit(.pounds)
        await appModel.settingsFeature.refreshCloudStatus()

        #expect(appModel.settingsFeature.selectedWeightUnit == .pounds)
        #expect(appModel.settingsFeature.cloudSyncStatus == .available)
    }

    @Test func rejectsWeightEntriesDatedInTheFuture() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let appModel = TestAppModelFactory.make(currentDate: { now })
        let draft = WeightEntryDraft(
            date: now.addingTimeInterval(1),
            value: "75"
        )

        await #expect(throws: WeightEntryFeature.EntryDateError.futureDate) {
            try await appModel.weightEntryFeature.save(draft, editing: nil)
        }
        #expect(appModel.weightEntryFeature.entries.isEmpty)
    }

    @Test func savingEntryRefreshesProgress() async throws {
        let repository = InMemoryWeightRepository()
        let appModel = TestAppModelFactory.make(repository: repository)

        await appModel.weightEntryFeature.refresh()
        try await appModel.weightEntryFeature.save(WeightEntryDraft(date: TestAppModelFactory.currentDate(), value: "75"), editing: nil)

        #expect(appModel.weightEntryFeature.entries.count == 1)
        #expect(appModel.progressFeature.progressSnapshot.points.count == 1)
    }
}

private actor StartupProbeRepository: WeightRepository, CloudSyncStatusProviding {
    private(set) var loadCallCount = 0
    private(set) var cloudStatusCallCount = 0
    private var released = false
    private var loadStarted = false
    private var cloudStatusStarted = false
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var cloudStatusContinuation: CheckedContinuation<Void, Never>?

    var didStartBothOperations: Bool { loadStarted && cloudStatusStarted }

    func load() async throws -> WeightStore {
        loadCallCount += 1
        loadStarted = true
        if !released { await withCheckedContinuation { loadContinuation = $0 } }
        return WeightStore(entries: [], goalKilograms: nil)
    }

    func save(_ store: WeightStore) async throws {}

    func cloudStatus() async -> CloudSyncStatus {
        cloudStatusCallCount += 1
        cloudStatusStarted = true
        if !released { await withCheckedContinuation { cloudStatusContinuation = $0 } }
        return .available
    }

    func releaseOperations() {
        released = true
        loadContinuation?.resume()
        loadContinuation = nil
        cloudStatusContinuation?.resume()
        cloudStatusContinuation = nil
    }
}
