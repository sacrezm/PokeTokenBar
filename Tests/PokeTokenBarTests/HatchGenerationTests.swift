import XCTest
@testable import PokeTokenBar

private struct GenerationProvider: PokeProviding {
    var restOnly = false
    var entries = [BaseSpecies(id: 1, captureRate: 255), BaseSpecies(id: 152, captureRate: 255),
                   BaseSpecies(id: 252, captureRate: 255), BaseSpecies(id: 387, captureRate: 255),
                   BaseSpecies(id: 494, captureRate: 255)]
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if restOnly { throw URLError(.notConnectedToInternet) }
        return entries
    }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: id, captureRate: 255) }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID,
                tree: EvoNode(speciesID: baseSpeciesID, children: [EvoNode(speciesID: 242, children: [])]),
                rarity: .common, names: [baseSpeciesID: ["en": "Test Pokémon"]])
    }
}

@MainActor
final class HatchGenerationTests: XCTestCase {
    func testGenerationBoundariesAndLegacySaveDefaults() throws {
        XCTAssertEqual(HatchGeneration.candidates(selected: [1, 2]), Array(1...251))
        for (id, gen) in [(1, 1), (151, 1), (152, 2), (251, 2), (252, 3), (386, 3),
                          (387, 4), (493, 4), (494, 5), (649, 5)] {
            XCTAssertTrue(HatchGeneration.contains(id, selected: [gen]))
            XCTAssertFalse(HatchGeneration.contains(id, selected: HatchGeneration.all.subtracting([gen])))
        }
        for json in ["{}", "{\"hatchGenerations\":[]}", "{\"hatchGenerations\":[99]}"] {
            let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
            XCTAssertEqual(state.hatchGenerations, HatchGeneration.all)
        }
    }

    func testIndexAndRESTHatchesStayWithinSelection() async throws {
        for restOnly in [false, true] {
            for seed: UInt64 in 1...12 {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: file) }
                var state = CompanionState()
                state.eggUsage = PokemonBalance.eggHatchThreshold + 1
                state.hatchGenerations = [1, 2]
                try JSONEncoder().encode(state).write(to: file)
                let store = CompanionStore(provider: GenerationProvider(restOnly: restOnly), fileURL: file,
                                           rng: SeededRNG(seed: seed))
                await store.hatchIfNeeded()
                let species = try XCTUnwrap(store.state.active?.baseID)
                XCTAssertTrue((1...251).contains(species), "REST=\(restOnly), species=\(species)")
            }
        }
    }

    func testSelectionPersistsAndInvalidatesOnlyExcludedPendingHatch() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.eggUsage = 1234
        state.eggTier = .rare
        state.pendingHatchID = 494
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: GenerationProvider(), fileURL: file)
        store.setHatchGenerations([1, 2])
        XCTAssertNil(store.state.pendingHatchID)
        XCTAssertEqual(store.state.eggUsage, 1234)
        XCTAssertEqual(store.state.eggTier, .rare)
        store.setHatchGenerations([])
        XCTAssertEqual(store.hatchGenerations, [1, 2])
        let restarted = CompanionStore(provider: GenerationProvider(), fileURL: file)
        XCTAssertEqual(restarted.hatchGenerations, [1, 2])
        await restarted.hatch(baseID: 494)
        XCTAssertNil(restarted.state.active)
    }

    func testExistingPokemonAndEvolutionPlanAreNotChanged() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CompanionStore(provider: GenerationProvider(), fileURL: file)
        store.setHatchGenerations([1])
        await store.hatch(baseID: 113)
        XCTAssertEqual(store.state.active?.plannedPathIDs, [113, 242], "Normal evolutions remain allowed")
        let before = try JSONEncoder().encode(store.state.active)
        store.setHatchGenerations([2])
        let after = try JSONEncoder().encode(store.state.active)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: before) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: after) as? NSDictionary)
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 0))
        XCTAssertEqual(store.state.active?.currentID, 242)
    }
}
