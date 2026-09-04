import XCTest
import SwiftUI
@testable import PokeTokenBar

final class OwnedCollectionTests: XCTestCase {
    private func entry(_ id: String, species: Int, chain: [Int]? = nil, released: Bool = false) -> DexEntry {
        DexEntry(id: id, baseID: chain?.first ?? species, finalID: species,
                 chainOrder: chain ?? [species], rarity: .common, caughtAt: nil,
                 names: [species: ["en": "Pokémon \(species)"]], releasedAt: released ? Date() : nil)
    }

    private func traded(_ id: String, species: Int) -> TradePokemon {
        TradePokemon(creatureID: id, speciesID: species, baseID: 63, chainOrder: [63, 64, species],
                     rarity: .common, isShiny: true, nature: .jolly, caughtAt: nil,
                     displayName: "Alakazam", originalTrainer: OriginalTrainer(trainerID: "ash", trainerName: "Ash"))
    }

    func testSixEvolutionStagesAreTwoOwnedPokemon() {
        let entries = [entry("one", species: 3, chain: [1, 2, 3]), entry("two", species: 6, chain: [4, 5, 6])]
        let result = OwnedCollection.pokemon(entries: entries, activeID: nil, held: [], transferredIDs: [], language: .en)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.speciesID), [3, 6])
        XCTAssertEqual(entries.map(\.chainOrder), [[1, 2, 3], [4, 5, 6]], "Do not rewrite species history")
    }

    func testDifferentIndividualsOfSameSpeciesAreNotCollapsed() {
        let entries = [entry("one", species: 25), entry("two", species: 25)]
        let result = OwnedCollection.pokemon(entries: entries, activeID: "two", held: [], transferredIDs: [], language: .en)
        XCTAssertEqual(result.map(\.id), ["two", "one"])
        XCTAssertTrue(result[0].isRaising)
        XCTAssertEqual(result.map(\.speciesID), [25, 25])
    }

    func testExcludesReleasedAndTradedAwayButIncludesReceivedAndActive() {
        let entries = [entry("released", species: 3, released: true), entry("sent", species: 6),
                       entry("raising", species: 2, chain: [1, 2, 3])]
        let result = OwnedCollection.pokemon(entries: entries, activeID: "raising",
                                             held: [traded("received", species: 65)], transferredIDs: ["sent"], language: .en)
        XCTAssertEqual(result.map(\.id), ["raising", "received"])
        XCTAssertEqual(result.map(\.speciesID), [2, 65])
        XCTAssertEqual(result[1].originalTrainer, "Ash")
        XCTAssertTrue(result[1].isShiny)
    }

    func testReturnedEvolvedIndividualOverridesOldCatchWithoutDoubleCounting() {
        let result = OwnedCollection.pokemon(entries: [entry("same", species: 64)], activeID: nil,
                                             held: [traded("same", species: 65)], transferredIDs: ["same"], language: .en)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.speciesID, 65)
        XCTAssertEqual(result.first?.name, "Alakazam")
    }

    func testLocalCatchAlreadyReconciledIntoTradingIsCountedOnce() {
        let result = OwnedCollection.pokemon(entries: [entry("same", species: 65)], activeID: nil,
                                             held: [traded("same", species: 65)], transferredIDs: [], language: .en)
        XCTAssertEqual(result.count, 1)
    }

    func testEmptyCollectionHasNoInventedPokemonOrEgg() {
        XCTAssertTrue(OwnedCollection.pokemon(entries: [], activeID: nil, held: [], transferredIDs: [], language: .en).isEmpty)
    }

    func testDetailsPreserveOriginalTrainerAndStoredStatsForReceivedPokemon() throws {
        let original = traded("individual", species: 65)
        let result = try XCTUnwrap(OwnedCollection.pokemon(entries: [], activeID: nil, held: [original],
                                                         transferredIDs: [], language: .en).first)
        XCTAssertEqual(result.originalTrainerLabel, "Ash")
        XCTAssertEqual(result.originalTrainerID, "ash")
        XCTAssertEqual(result.nature, .jolly)
        XCTAssertEqual(result.rarity, .common)
        XCTAssertTrue(result.isShiny)
        XCTAssertEqual(result.generationLabel, "Gen 1 · Kanto")
        XCTAssertEqual(result.recordedAt, original.caughtAt)
        XCTAssertEqual(result.id, original.creatureID)
    }

    func testOldLocalRecordsDoNotInventTrainerNatureOrDates() throws {
        let original = entry("old", species: 25)
        let result = try XCTUnwrap(OwnedCollection.pokemon(entries: [original], activeID: nil, held: [],
                                                         transferredIDs: [], language: .en).first)
        XCTAssertNil(result.originalTrainer)
        XCTAssertNil(result.originalTrainerID)
        XCTAssertEqual(result.originalTrainerLabel, "Not recorded")
        XCTAssertNil(result.nature)
        XCTAssertNil(result.recordedAt)
    }

    func testDetailsUseExactSavedDateWithoutReplacingItWithToday() throws {
        var original = entry("dated", species: 531)
        original.caughtAt = Date(timeIntervalSince1970: 123456)
        original.nature = .timid
        let result = try XCTUnwrap(OwnedCollection.pokemon(entries: [original], activeID: nil, held: [],
                                                         transferredIDs: [], language: .en).first)
        XCTAssertEqual(result.recordedAt, original.caughtAt)
        XCTAssertEqual(result.nature, .timid)
        XCTAssertEqual(result.generationLabel, "Gen 5 · Unova")
    }

    @MainActor
    func testDetailPageFitsPopoverWithLongTrainerNameAndIdentifier() throws {
        let original = TradePokemon(creatureID: String(repeating: "a", count: 64), speciesID: 65,
                                    baseID: 63, chainOrder: [63, 64, 65], rarity: .rare,
                                    isShiny: true, nature: .jolly, caughtAt: Date(timeIntervalSince1970: 100),
                                    displayName: "Alakazam", originalTrainer: OriginalTrainer(
                                        trainerID: String(repeating: "b", count: 64),
                                        trainerName: "A trainer with a very long display name"))
        let pokemon = try XCTUnwrap(OwnedCollection.pokemon(entries: [], activeID: nil, held: [original],
                                                          transferredIDs: [], language: .en).first)
        let controller = NSHostingController(rootView: OwnedPokemonDetailView(pokemon: pokemon, language: .en, onBack: {})
            .frame(width: PopoverMetrics.contentWidth, height: 488))
        let size = controller.sizeThatFits(in: CGSize(width: PopoverMetrics.contentWidth, height: 488))
        XCTAssertLessThanOrEqual(size.width, PopoverMetrics.contentWidth)
        XCTAssertEqual(size.height, 488, accuracy: 1)
    }

    @MainActor
    func testAllThreeCollectionTabsFitThePopover() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CompanionStore(fileURL: file)
        let nav = PopoverNavigation()
        for tab in [CollectionTab.owned, .pokedex, .catchLog] {
            nav.collectionTab = tab
            let controller = NSHostingController(rootView: CollectionView(store: store, navigation: nav)
                .frame(width: PopoverMetrics.contentWidth))
            let size = controller.sizeThatFits(in: CGSize(width: PopoverMetrics.contentWidth, height: 600))
            XCTAssertLessThanOrEqual(size.width, PopoverMetrics.contentWidth)
            XCTAssertEqual(size.height, 520, accuracy: 1)
        }
    }
}
