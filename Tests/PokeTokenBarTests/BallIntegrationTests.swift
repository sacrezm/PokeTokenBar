import XCTest
@testable import PokeTokenBar

@MainActor
final class BallIntegrationTests: XCTestCase {
    private struct SlowIndexProvider: PokeProviding {
        func line(baseSpeciesID: Int) async throws -> EvoLine {
            EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                    names: [25: ["en": "Pikachu"]])
        }
        func baseSpeciesIndex() async throws -> [BaseSpecies] {
            try await Task.sleep(for: .milliseconds(10))
            return [BaseSpecies(id: 25, captureRate: 190)]
        }
    }

    private actor RetryLineProvider: PokeProviding {
        private var shouldFail = true
        func line(baseSpeciesID: Int) async throws -> EvoLine {
            if shouldFail { shouldFail = false; throw URLError(.notConnectedToInternet) }
            return EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                           names: [25: ["en": "Pikachu"]])
        }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 25, captureRate: 190)] }
    }
    private func store(_ state: CompanionState = CompanionState()) throws -> (CompanionStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let line = EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []),
                           rarity: .common, names: [25: ["en": "Pikachu"]])
        return (CompanionStore(provider: StubProvider(value: line), fileURL: url), url)
    }

    func testPurchaseConsumesWalletOnlyAndEquippingPersistsOnce() throws {
        var state = CompanionState()
        state.usedSinceInstall = CatchingBall.quickBall.price
        let (store, url) = try store(state)
        XCTAssertTrue(store.buyBall(.quickBall))
        XCTAssertEqual(store.availableTokens, 0)
        XCTAssertEqual(store.state.eggUsage, 0)
        XCTAssertEqual(store.ballCount(.quickBall), 1)
        XCTAssertFalse(store.buyBall(.quickBall))
        XCTAssertTrue(store.queueBall(.quickBall))
        XCTAssertEqual(store.ballCount(.quickBall), 0)
        XCTAssertEqual(store.eggBall, .quickBall)
        XCTAssertEqual(store.eggTokensToHatch, 400_000)
        let reopened = CompanionStore(fileURL: url)
        XCTAssertEqual(reopened.eggBall, .quickBall)
        XCTAssertEqual(reopened.ballCount(.quickBall), 0)
        XCTAssertEqual(reopened.eggTokensToHatch, 400_000)
        XCTAssertFalse(reopened.queueBall(.quickBall))
    }

    func testStartedEggQueuesInsteadOfChangingItsAlreadyRolledOutcome() throws {
        var state = CompanionState()
        state.eggUsage = 1
        state.pendingHatchID = 25
        state.ballInventory[CatchingBall.greatBall.rawValue] = 1
        let (store, _) = try store(state)
        XCTAssertTrue(store.queueBall(.greatBall))
        XCTAssertNil(store.eggBall)
        XCTAssertEqual(store.queuedBall, .greatBall)
        XCTAssertEqual(store.state.pendingHatchID, 25)
        XCTAssertEqual(store.ballCount(.greatBall), 1)
        store.clearQueuedBall()
        XCTAssertNil(store.queuedBall)
        XCTAssertEqual(store.ballCount(.greatBall), 1)
    }

    func testUntouchedEggEquipmentInvalidatesPrefetchedSpecies() throws {
        var state = CompanionState()
        state.pendingHatchID = 25
        state.ballInventory[CatchingBall.ultraBall.rawValue] = 1
        let (store, _) = try store(state)
        XCTAssertTrue(store.queueBall(.ultraBall))
        XCTAssertNil(store.state.pendingHatchID)
        XCTAssertEqual(store.eggBall, .ultraBall)
    }

    func testLuxuryHatchGetsBonusOnlyOnceAndNoEVs() async throws {
        var state = CompanionState()
        state.ballInventory[CatchingBall.luxuryBall.rawValue] = 1
        let (store, _) = try store(state)
        XCTAssertTrue(store.queueBall(.luxuryBall))
        await store.hatch(baseID: 25)
        XCTAssertEqual(store.state.active?.progression.level, 10)
        XCTAssertEqual(store.state.active?.progression.totalEVs, 0)
        XCTAssertNil(store.eggBall)
        store.applyUsage(PokemonBalance.graduationTotal(.common))
        await store.hatch(baseID: 25)
        XCTAssertEqual(store.state.active?.progression.level, 5)
    }

    func testQueueConsumesOneBallAtGraduationNotBefore() async throws {
        var state = CompanionState()
        state.ballInventory[CatchingBall.pokeBall.rawValue] = 2
        let (store, _) = try store(state)
        await store.hatch(baseID: 25)
        XCTAssertTrue(store.queueBall(.pokeBall))
        XCTAssertEqual(store.ballCount(.pokeBall), 2)
        store.applyUsage(PokemonBalance.graduationTotal(.common))
        XCTAssertEqual(store.ballCount(.pokeBall), 1)
        XCTAssertEqual(store.eggBall, .pokeBall)
        XCTAssertNil(store.queuedBall)
    }

    func testFirstThresholdUpdateHatchesAfterSuspendedPrefetchWithoutSecondRefresh() async throws {
        var state = CompanionState()
        state.installBaselineSet = true
        state.claimedTodayTokensByProvider = ["test": 0]
        state.lastDate = "test"
        state.eggBall = .quickBall
        let (_, url) = try store(state)
        let store = CompanionStore(provider: SlowIndexProvider(), fileURL: url)
        store.update(todayTokensByProvider: ["test": 500_000], todayDate: "test", monthTotal: 500_000,
                     burnTier: .normal, limitWarning: false, hasUsageData: true)
        for _ in 0..<200 {
            if store.state.active != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(store.currentSpeciesID, 25)
        XCTAssertEqual(store.state.active?.usedAtStage, 100_000)
        XCTAssertNil(store.eggBall)
        XCTAssertEqual(store.state.usedSinceInstall, 500_000)
    }

    func testFailedLineFetchRetainsPaidEggAndPrerolledSpeciesAcrossRestart() async throws {
        var state = CompanionState()
        state.eggUsage = PokemonBalance.eggHatchThreshold
        state.eggBall = .ultraBall
        state.pendingHatchID = 25
        let (_, url) = try store(state)
        let provider = RetryLineProvider()
        let original = CompanionStore(provider: provider, fileURL: url)
        await original.hatchIfNeeded()
        XCTAssertNil(original.state.active)
        XCTAssertEqual(original.state.pendingHatchID, 25)
        XCTAssertEqual(original.eggBall, .ultraBall)
        let retry = CompanionStore(provider: provider, fileURL: url)
        XCTAssertEqual(retry.state.pendingHatchID, 25)
        await retry.hatchIfNeeded()
        XCTAssertEqual(retry.currentSpeciesID, 25)
        XCTAssertNil(retry.state.pendingHatchID)
        XCTAssertNil(retry.eggBall)
    }

    func testPaidMutationsRollBackWhenTheSaveCannotBeWritten() throws {
        var state = CompanionState()
        state.usedSinceInstall = 10_000_000
        state.ballInventory[CatchingBall.quickBall.rawValue] = 1
        state.inventory[ItemKind.rareCandy.rawValue] = 1
        state.dex = [DexEntry(id: "test", baseID: 25, finalID: 25, chainOrder: [25], rarity: .common, caughtAt: nil)]
        let (store, url) = try store(state)
        // This URL belongs to the temporary fixture above, never the user's save.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertFalse(store.buyBall(.quickBall))
        XCTAssertEqual(store.availableTokens, 10_000_000)
        XCTAssertEqual(store.ballCount(.quickBall), 1)
        XCTAssertFalse(store.queueBall(.quickBall))
        XCTAssertNil(store.eggBall)
        XCTAssertEqual(store.ballCount(.quickBall), 1)
        XCTAssertFalse(store.useTrainingCandy())
        XCTAssertEqual(store.rareCandyCount, 1)
        XCTAssertEqual(store.trainingPokemon?.progression.level, 5)
        XCTAssertNotNil(store.persistenceError)
    }
}
