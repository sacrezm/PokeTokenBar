import XCTest
import SwiftUI
@testable import PokeTokenBar

final class TradeEvolutionTests: XCTestCase {
    private func pokemon(_ species: Int, id: String = "incoming", name: String = "Kadabra") -> TradePokemon {
        TradePokemon(creatureID: id, speciesID: species, baseID: species, chainOrder: [species],
                     rarity: .rare, isShiny: true, nature: .jolly,
                     caughtAt: Date(timeIntervalSince1970: 100), displayName: name,
                     originalTrainer: OriginalTrainer(trainerID: "original", trainerName: "Ash"))
    }

    func testTradeOnlyRulesPreserveIndividualAndEvolveJustOneStage() {
        for (before, after, name) in [(64, 65, "Alakazam"), (67, 68, "Machamp"),
                                    (75, 76, "Golem"), (93, 94, "Gengar"),
                                    (525, 526, "Gigalith"), (533, 534, "Conkeldurr")] {
            let original = pokemon(before)
            let result = TradeEvolution.received(original, exchangedFor: 25)
            XCTAssertEqual(result.speciesID, after)
            XCTAssertEqual(result.displayName, name)
            XCTAssertEqual(result.chainOrder, [before, after])
            XCTAssertEqual(result.creatureID, original.creatureID)
            XCTAssertEqual(result.originalTrainer, original.originalTrainer)
            XCTAssertEqual(result.baseID, original.baseID)
            XCTAssertEqual(result.caughtAt, original.caughtAt)
            XCTAssertEqual(result.isShiny, original.isShiny)
            XCTAssertEqual(result.nature, original.nature)
            XCTAssertEqual(result.rarity, original.rarity)
            XCTAssertEqual(TradeEvolution.received(result, exchangedFor: 25), result)
        }
    }

    func testPairedEvolutionsRequireTheOtherSpecies() {
        for (before, partner, after) in [(588, 616, 589), (616, 588, 617)] {
            let original = pokemon(before)
            XCTAssertEqual(TradeEvolution.received(original, exchangedFor: partner).speciesID, after)
            XCTAssertEqual(TradeEvolution.received(original, exchangedFor: 25), original)
            XCTAssertEqual(TradeEvolution.received(original, exchangedFor: before), original)
        }
    }

    func testItemDependentAndOrdinarySpeciesAreUnchanged() {
        for species in [25, 61, 79, 95, 123, 117, 137, 366, 112, 125, 126, 233, 356, 349] {
            let original = pokemon(species)
            XCTAssertEqual(TradeEvolution.received(original, exchangedFor: 25), original)
        }
    }

    @MainActor
    func testCommitPersistsEvolutionAndNotifiesOnceAcrossRetriesAndRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("trades.json")
        let sidecar = TradingSidecar(fileURL: url)
        _ = try await sidecar.reconcile(local: [pokemon(25, id: "outgoing")])
        let suite = "trade-evolution-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let feature = TradingFeature(baseURL: URL(string: "https://example.test")!,
                                     identityStore: try InMemoryTradingIdentityStore(),
                                     sidecar: sidecar, defaults: defaults)
        var events: [TradingActivity] = []
        feature.onActivity = { events.append($0) }
        let receipt = TradeReceipt(receiptID: "r", tradeID: "t", outgoingCreatureID: "outgoing",
                                   incoming: pokemon(64))
        try await feature.applyLocalReceipt(receipt)
        XCTAssertEqual(feature.receivedPokemon(for: receipt).speciesID, 65)
        XCTAssertEqual(feature.heldInventory.map(\.speciesID), [65])
        XCTAssertEqual(feature.receivedInventory.map(\.speciesID), [65])
        XCTAssertEqual(feature.completion?.incoming.speciesID, 64, "Keep the before sprite for the animation")
        XCTAssertEqual(events.first?.body, "Kadabra evolved into Alakazam!")
        let projected = TradingCollectionProjection.species(original: [], received: feature.receivedInventory)
        XCTAssertEqual(projected.map(\.id), [65])
        feature.dismissCompletion()
        try await feature.applyLocalReceipt(receipt)
        XCTAssertNil(feature.completion)
        XCTAssertEqual(events.count, 1)
        let restarted = TradingSidecar(fileURL: url)
        let replay = try await restarted.apply(receipt)
        XCTAssertEqual(replay, .alreadyApplied)
        let saved = try await restarted.state()
        XCTAssertEqual(saved.heldInventory.first?.speciesID, 65)
        XCTAssertEqual(saved.heldInventory.first?.originalTrainer, receipt.incoming.originalTrainer)
        XCTAssertEqual(saved.appliedReceiptIDs, ["r"])
    }

    func testPairedTradeEvolvesBothSidesAndCanBeTradedBack() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = TradingSidecar(fileURL: dir.appendingPathComponent("a.json"))
        let b = TradingSidecar(fileURL: dir.appendingPathComponent("b.json"))
        let karrablast = pokemon(588, id: "k", name: "Karrablast")
        let shelmet = pokemon(616, id: "s", name: "Shelmet")
        _ = try await a.reconcile(local: [karrablast])
        _ = try await b.reconcile(local: [shelmet])
        _ = try await a.apply(TradeReceipt(receiptID: "1", tradeID: "1", outgoingCreatureID: "k", incoming: shelmet))
        _ = try await b.apply(TradeReceipt(receiptID: "1", tradeID: "1", outgoingCreatureID: "s", incoming: karrablast))
        let aHeld = try await a.heldInventory()
        let bHeld = try await b.heldInventory()
        let accelgor = try XCTUnwrap(aHeld.first)
        let escavalier = try XCTUnwrap(bHeld.first)
        XCTAssertEqual(accelgor.speciesID, 617)
        XCTAssertEqual(escavalier.speciesID, 589)
        _ = try await a.apply(TradeReceipt(receiptID: "2", tradeID: "2", outgoingCreatureID: "s", incoming: escavalier))
        _ = try await b.apply(TradeReceipt(receiptID: "2", tradeID: "2", outgoingCreatureID: "k", incoming: accelgor))
        // Once more exercises the already-received creature path without duplicating records.
        _ = try await a.apply(TradeReceipt(receiptID: "3", tradeID: "3", outgoingCreatureID: "k", incoming: accelgor))
        let state = try await a.state()
        XCTAssertEqual(state.heldInventory, [accelgor])
        XCTAssertEqual(state.receivedInventory.count, 2)
    }

    func testLegacyReceivedFormMayReturnEvolvedButNotAsUnrelatedSpecies() {
        let old = pokemon(64)
        let evolved = TradeEvolution.received(old, exchangedFor: 25)
        XCTAssertTrue(TradeEvolution.isReturning(evolved, previously: old))
        XCTAssertFalse(TradeEvolution.isReturning(old, previously: evolved), "No devolution")
        XCTAssertFalse(TradeEvolution.isReturning(pokemon(25), previously: old))
    }

    @MainActor
    func testEvolutionCardFitsPopover() {
        let before = pokemon(533, name: "Gurdurr")
        let receipt = TradeReceipt(receiptID: "layout", tradeID: "layout", outgoingCreatureID: "out", incoming: before)
        let view = TradeCompletionView(receipt: receipt, received: TradeEvolution.received(before, exchangedFor: 25),
                                       onDismiss: {})
        let controller = NSHostingController(rootView: view.frame(width: PopoverMetrics.contentWidth))
        let size = controller.sizeThatFits(in: CGSize(width: PopoverMetrics.contentWidth, height: 150))
        XCTAssertLessThanOrEqual(size.width, PopoverMetrics.contentWidth)
        XCTAssertLessThanOrEqual(size.height, 100)
    }
}
