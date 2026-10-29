// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
@testable import Trend

@MainActor
final class InMemoryPurchaseClient: PurchaseClient {
    var product = PurchaseProduct(
        id: PurchaseFeature.habitsProductID,
        displayName: "Trend Habits",
        description: "Track the daily signals that matter to you.",
        displayPrice: "£4.99"
    )
    private(set) var observationCount = 0
    var productResponse: (@MainActor () async throws -> PurchaseProduct?)?
    var entitlementResponse: (@MainActor () async -> Bool)?
    var hasPurchased = false
    var nextOutcome: PurchaseOutcome = .purchased
    var productError: (any Error)?
    private let updates: AsyncStream<Void>
    private let updateContinuation: AsyncStream<Void>.Continuation

    init() {
        let transactionUpdates = AsyncStream<Void>.makeStream()
        updates = transactionUpdates.stream
        updateContinuation = transactionUpdates.continuation
    }

    func product(withID id: String) async throws -> PurchaseProduct? {
        if let productResponse { return try await productResponse() }
        if let productError { throw productError }
        return product
    }

    func purchase(productID: String) async throws -> PurchaseOutcome {
        if case .purchased = nextOutcome { hasPurchased = true }
        return nextOutcome
    }

    func hasEntitlement(for productID: String) async -> Bool {
        if let entitlementResponse { return await entitlementResponse() }
        return hasPurchased
    }
    func restore() async throws {}
    func transactionUpdates() -> AsyncStream<Void> {
        observationCount += 1
        return updates
    }

    func completePurchaseOutsideThePurchaseSheet() {
        hasPurchased = true
        updateContinuation.yield()
    }
}
