import Foundation
import XCTest
@testable import PokeTokenBar

final class TradingProgressionTests: XCTestCase {
    private let preservedProgression = PokemonProgression(
        totalExperience: 1_000,
        evs: [.attack: 7, .speed: 3],
        trainingRemainder: 42
    )

    private func pokemon(
        id: String = "individual",
        species: Int = 25,
        progression: PokemonProgression = PokemonProgression(),
        trainerID: String = "ash",
        trainerName: String = "Ash"
    ) -> TradePokemon {
        TradePokemon(
            creatureID: id,
            speciesID: species,
            baseID: species,
            chainOrder: [species],
            rarity: .common,
            isShiny: false,
            nature: nil,
            caughtAt: Date(timeIntervalSince1970: 100),
            displayName: "Pokémon #\(species)",
            originalTrainer: OriginalTrainer(trainerID: trainerID, trainerName: trainerName),
            progression: progression
        )
    }

    func testLegacyTradePayloadDefaultsMissingProgressionToFreshLevelFiveState() throws {
        let legacyPayload = #"""
        {
            "caughtAt": "1970-01-01T00:01:40Z",
            "chainOrder": [25],
            "creatureID": "legacy",
            "displayName": "Pikachu",
            "isShiny": false,
            "nature": null,
            "originalTrainer": {"trainerID": "ash", "trainerName": "Ash"},
            "rarity": "common",
            "speciesID": 25,
            "baseID": 25
        }
        """#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TradePokemon.self, from: Data(legacyPayload.utf8))

        XCTAssertEqual(decoded.progression, PokemonProgression())
        XCTAssertEqual(decoded.progression.level, PokemonProgression.startingLevel)
    }

    func testTradePayloadRoundTripPreservesIndividualProgression() throws {
        let original = pokemon(progression: preservedProgression)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TradePokemon.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.progression, preservedProgression)
    }

    func testCollectionAndLocalTradeProjectionPreserveProgression() throws {
        let entry = DexEntry(
            id: "graduated",
            baseID: 25,
            finalID: 25,
            chainOrder: [25],
            rarity: .common,
            caughtAt: Date(timeIntervalSince1970: 100),
            names: [25: ["en": "Pikachu"]],
            progression: preservedProgression
        )
        let projected = CompanionCollectionAdapter(state: CompanionState.withDex([entry]))
            .snapshot(trainerID: "ash", trainerName: "Ash")
        let owned = OwnedCollection.pokemon(
            entries: [entry],
            activeID: nil,
            held: [pokemon(id: "received", progression: preservedProgression)],
            transferredIDs: [],
            language: .en
        )

        XCTAssertEqual(projected.first?.progression, preservedProgression)
        XCTAssertEqual(owned.first(where: { $0.id == "graduated" })?.progression, preservedProgression)
        XCTAssertEqual(owned.first(where: { $0.id == "received" })?.progression, preservedProgression)
    }

    func testTradeEvolutionPreservesIndividualProgression() {
        let original = pokemon(species: 64, progression: preservedProgression)

        let evolved = TradeEvolution.received(original, exchangedFor: 25)

        XCTAssertEqual(evolved.speciesID, 65)
        XCTAssertEqual(evolved.progression, preservedProgression)
    }

    func testProgressPreservationAcceptsXPAdvanceWhenEVCarryRollsOver() {
        let existing = PokemonProgression(
            totalExperience: 1_000,
            evs: [.attack: PokemonProgression.maxEVPerStat],
            trainingRemainder: PokemonProgression.tokensPerEV - 1
        )
        let incoming = PokemonProgression(
            totalExperience: 2_000,
            evs: [.attack: PokemonProgression.maxEVPerStat],
            trainingRemainder: 0
        )

        XCTAssertEqual(
            PokemonProgression.preservingProgress(existing: existing, incoming: incoming),
            incoming
        )
    }

    func testProgressPreservationAcceptsEVAdvanceAtLevel100WhenXPCarryRollsOver() {
        let existing = PokemonProgression(
            totalExperience: PokemonProgression.maxExperience,
            evs: [.attack: 1],
            experienceRemainder: PokemonProgression.tokensPerExperience - 1
        )
        let incoming = PokemonProgression(
            totalExperience: PokemonProgression.maxExperience,
            evs: [.attack: 2],
            experienceRemainder: 0
        )

        XCTAssertEqual(
            PokemonProgression.preservingProgress(existing: existing, incoming: incoming),
            incoming
        )
    }

    func testReconcileUpdatesOnlyLocalHeldProgression() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sidecar = TradingSidecar(fileURL: url)
        let initial = pokemon(id: "local", progression: PokemonProgression())
        let updated = pokemon(id: "local", progression: preservedProgression, trainerName: "Gary")

        _ = try await sidecar.reconcile(local: [initial])
        _ = try await sidecar.reconcile(local: [updated])

        let held = try await sidecar.heldInventory()
        XCTAssertEqual(held.first?.progression, preservedProgression)
        XCTAssertEqual(held.first?.originalTrainer, initial.originalTrainer)
    }

    func testReconcileAppliesOverridesOnlyToHeldAndMirrorsReceivedHistory() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sidecar = TradingSidecar(fileURL: url)
        let local = pokemon(id: "local")
        let received = pokemon(id: "received")
        let historyOnly = pokemon(id: "history-only")
        try write(
            TradingSidecarState(
                heldInventory: [local, received],
                receivedInventory: [received, historyOnly]
            ),
            to: url
        )

        _ = try await sidecar.reconcile(
            local: [],
            progressionOverrides: [
                local.creatureID: preservedProgression,
                received.creatureID: preservedProgression,
                historyOnly.creatureID: preservedProgression,
            ]
        )

        let state = try await sidecar.state()
        XCTAssertEqual(state.heldInventory.first(where: { $0.creatureID == local.creatureID })?.progression,
                       preservedProgression)
        XCTAssertEqual(state.heldInventory.first(where: { $0.creatureID == received.creatureID })?.progression,
                       preservedProgression)
        XCTAssertEqual(state.receivedInventory.first(where: { $0.creatureID == received.creatureID })?.progression,
                       preservedProgression)
        XCTAssertEqual(state.receivedInventory.first(where: { $0.creatureID == historyOnly.creatureID })?.progression,
                       historyOnly.progression)
    }

    func testStaleLocalReconcileCannotDowngradeReturnedProgression() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sidecar = TradingSidecar(fileURL: url)
        let returned = pokemon(id: "returned", progression: preservedProgression, trainerID: "peer", trainerName: "Misty")
        let outgoing = pokemon(id: "outgoing")
        let state = TradingSidecarState(
            heldInventory: [outgoing, returned],
            receivedInventory: [returned],
            transferredIDs: [returned.creatureID]
        )
        try write(state, to: url)

        _ = try await sidecar.reconcile(local: [pokemon(id: "returned", progression: PokemonProgression())])

        let saved = try await sidecar.state()
        XCTAssertEqual(saved.heldInventory.first(where: { $0.creatureID == returned.creatureID })?.progression,
                       preservedProgression)
        XCTAssertEqual(saved.receivedInventory.first?.progression, preservedProgression)
    }

    func testReturnedPayloadCannotReplaceNewerSavedProgression() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sidecar = TradingSidecar(fileURL: url)
        let saved = pokemon(id: "returned", progression: preservedProgression, trainerID: "peer", trainerName: "Misty")
        let outgoing = pokemon(id: "outgoing")
        let state = TradingSidecarState(
            heldInventory: [outgoing],
            receivedInventory: [saved],
            transferredIDs: [saved.creatureID]
        )
        try write(state, to: url)

        let stale = pokemon(id: "returned", progression: PokemonProgression(), trainerID: "peer", trainerName: "Misty")
        let receipt = TradeReceipt(
            receiptID: "return-receipt",
            tradeID: "return-trade",
            outgoingCreatureID: outgoing.creatureID,
            incoming: stale
        )

        let result = try await sidecar.apply(receipt)
        XCTAssertEqual(result, .applied)
        let after = try await sidecar.state()
        XCTAssertEqual(after.heldInventory.first(where: { $0.creatureID == saved.creatureID })?.progression,
                       preservedProgression)
        XCTAssertEqual(after.receivedInventory.first(where: { $0.creatureID == saved.creatureID })?.progression,
                       preservedProgression)
    }

    @MainActor
    func testFeatureInventoryRefreshPublishesOwnershipSnapshot() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let received = pokemon(id: "received", progression: preservedProgression)
        let state = TradingSidecarState(
            heldInventory: [received],
            receivedInventory: [received],
            transferredIDs: ["transferred"]
        )
        try write(state, to: url)

        let suite = "trading-progress-callback-(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let feature = TradingFeature(
            baseURL: URL(string: "https://example.test")!,
            identityStore: try InMemoryTradingIdentityStore(),
            sidecar: TradingSidecar(fileURL: url),
            defaults: defaults
        )
        var snapshots: [([TradePokemon], [TradePokemon], Set<String>)] = []
        feature.onInventoryChange = { held, received, transferred in
            snapshots.append((held, received, transferred))
        }

        try await feature.refreshLocalInventory()

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.0, [received])
        XCTAssertEqual(snapshots.first?.1, [received])
        XCTAssertEqual(snapshots.first?.2, ["transferred"])
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("trading-progression-\(UUID().uuidString).json")
    }

    private func write(_ state: TradingSidecarState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url)
    }
}

private extension CompanionState {
    static func withDex(_ entries: [DexEntry]) -> CompanionState {
        var state = CompanionState()
        state.dex = entries
        return state
    }
}
