import XCTest
@testable import PokeTokenBar

@MainActor
final class TrainingIntegrationTests: XCTestCase {
    private func store(_ state: CompanionState = CompanionState()) throws -> (CompanionStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("companion-state.json")
        try JSONEncoder().encode(state).write(to: url)
        let line = EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []),
                           rarity: .common, names: [25: ["en": "Pikachu"]])
        return (CompanionStore(provider: StubProvider(value: line), fileURL: url), url)
    }

    private func ownedState() -> CompanionState {
        var state = CompanionState()
        state.dex = [DexEntry(id: "trainee", baseID: 25, finalID: 25, chainOrder: [25],
                              rarity: .common, caughtAt: nil)]
        return state
    }

    func testTrainingOnlyGainsXPAndEVWithoutAdvancingEgg() throws {
        let (store, url) = try store(ownedState())
        store.setTrainingMode(.training)
        store.setTrainingFocus(.hp)
        store.routeGameplayTokens(1_000_000)
        XCTAssertEqual(store.state.eggUsage, 0)
        XCTAssertEqual(store.trainingPokemon?.progression.totalExperience, 1_125)
        XCTAssertEqual(store.trainingPokemon?.progression.level, 10)
        XCTAssertEqual(store.trainingPokemon?.progression.evs[.hp], 10)
        let reopened = CompanionStore(fileURL: url)
        XCTAssertEqual(reopened.trainingPokemon?.progression, store.trainingPokemon?.progression)
        XCTAssertEqual(reopened.trainingMode, .training)
    }

    func testBalancedAllocationIsIndependentOfRefreshChunking() throws {
        let (one, _) = try store(ownedState())
        let (many, _) = try store(ownedState())
        one.setTrainingMode(.balanced)
        many.setTrainingMode(.balanced)
        one.routeGameplayTokens(2_003)
        for _ in 0..<2_003 { many.routeGameplayTokens(1) }
        XCTAssertEqual(one.state.eggUsage, many.state.eggUsage)
        XCTAssertEqual(one.trainingPokemon?.progression, many.trainingPokemon?.progression)
        XCTAssertEqual(one.state.splitRemainder, many.state.splitRemainder)
    }

    func testNoTraineeFallsBackToCatchWithoutLosingTokens() throws {
        let (store, _) = try store()
        store.setTrainingMode(.training)
        store.routeGameplayTokens(10_000)
        XCTAssertEqual(store.state.eggUsage, 10_000)
    }

    func testTransferredPokemonCannotReceiveTraining() throws {
        let (store, _) = try store(ownedState())
        store.setTrainingTarget("trainee")
        store.setTrainingMode(.training)
        store.setTrainingExcludedIDs(["trainee"])
        store.routeGameplayTokens(100_000)
        XCTAssertNil(store.trainingPokemon)
        XCTAssertEqual(store.state.dex[0].progression.totalExperience, 125)
        XCTAssertEqual(store.state.eggUsage, 100_000)
    }

    func testCandyAddsOneLevelNoEVNoCatchProgressAndNoWalletIncome() throws {
        var state = ownedState()
        state.inventory[ItemKind.rareCandy.rawValue] = 1
        let (store, _) = try store(state)
        XCTAssertEqual(store.useRareCandy(), .progressed)
        XCTAssertEqual(store.trainingPokemon?.progression.level, 6)
        XCTAssertEqual(store.trainingPokemon?.progression.evs[.hp], 0)
        XCTAssertEqual(store.rareCandyCount, 0)
        XCTAssertEqual(store.state.usedSinceInstall, 0)
        XCTAssertEqual(store.state.eggUsage, 0)
        XCTAssertEqual(store.useRareCandy(), .unavailable)
    }

    func testActiveIdentityAndProgressionSurviveGraduationWithOverflow() async throws {
        let (store, _) = try store()
        await store.hatch(baseID: 25)
        let id = try XCTUnwrap(store.state.active?.id)
        store.setTrainingTarget(id)
        store.setTrainingMode(.training)
        store.routeGameplayTokens(100_000)
        let trained = try XCTUnwrap(store.state.active?.progression)
        store.setTrainingMode(.catching)
        store.routeGameplayTokens(PokemonBalance.graduationTotal(.common) + 42)
        XCTAssertNil(store.state.active)
        XCTAssertEqual(store.state.dex.last?.id, id)
        XCTAssertEqual(store.state.dex.last?.progression.evs, trained.evs)
        XCTAssertEqual(store.state.eggUsage, 42)
        XCTAssertEqual(store.trainingPokemon?.id, id)
    }

    func testUsageLedgerDoesNotReplayTrainingAcrossRefreshOrRestart() throws {
        var state = ownedState()
        state.installBaselineSet = true
        state.claimedTodayTokensByProvider = ["test": 100]
        state.lastDate = "2026-09-04"
        state.trainingMode = .training
        let (store, url) = try store(state)
        func update(_ store: CompanionStore) {
            store.update(todayTokensByProvider: ["test": 100_100], todayDate: "2026-09-04",
                         monthTotal: 100_100, burnTier: .idle, limitWarning: false, hasUsageData: true)
        }
        update(store)
        let progress = store.trainingPokemon?.progression
        update(store)
        XCTAssertEqual(store.trainingPokemon?.progression, progress)
        let reopened = CompanionStore(fileURL: url)
        update(reopened)
        XCTAssertEqual(reopened.trainingPokemon?.progression, progress)
        XCTAssertEqual(reopened.state.usedSinceInstall, 100_000)
    }

    func testReceivedTrainingUsesLocalUsageTransactionAndDoesNotResetOnStaleSnapshot() throws {
        let (store, url) = try store()
        let received = TradePokemon(creatureID: "received", speciesID: 25, baseID: 25,
                                    chainOrder: [25], rarity: .common, isShiny: false,
                                    nature: .jolly, caughtAt: nil, displayName: "Pikachu",
                                    originalTrainer: OriginalTrainer(trainerID: "friend", trainerName: "Friend"))
        store.syncTrainingOwnership(held: [received], received: [received], transferredIDs: [])
        store.setTrainingTarget(received.creatureID)
        store.setTrainingMode(.training)
        store.routeGameplayTokens(100_000)
        let progress = try XCTUnwrap(store.trainingPokemon?.progression)
        XCTAssertEqual(progress.totalExperience, 225)
        XCTAssertEqual(progress.totalEVs, 1)
        let reopened = CompanionStore(fileURL: url)
        XCTAssertNil(reopened.trainingPokemon, "Received Pokémon stay gated until ownership is loaded")
        reopened.syncTrainingOwnership(held: [received], received: [received], transferredIDs: [])
        XCTAssertEqual(reopened.trainingPokemon?.progression, progress)
        XCTAssertEqual(reopened.trainedVersion(received).progression, progress)
        reopened.syncTrainingOwnership(held: [], received: [received], transferredIDs: [received.creatureID])
        XCTAssertNil(reopened.trainingPokemon)
        reopened.routeGameplayTokens(1_000)
        XCTAssertEqual(reopened.state.eggUsage, 1_000)
        XCTAssertEqual(reopened.state.receivedTraining[0].progression, progress)
    }

    func testTradeLockExcludesSelectedTraineeFromCandyAndUsage() throws {
        var state = ownedState()
        state.dex.append(DexEntry(id: "other", baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: nil))
        state.inventory[ItemKind.rareCandy.rawValue] = 1
        let (store, _) = try store(state)
        store.setTrainingTarget("trainee")
        store.setTrainingMode(.training)
        store.setTrainingLockedIDs(["trainee"])
        XCTAssertFalse(store.canUseTrainingCandy)
        XCTAssertFalse(store.useTrainingCandy())
        store.routeGameplayTokens(100_000)
        XCTAssertEqual(store.state.dex[0].progression.totalExperience, 125)
        XCTAssertEqual(store.state.dex[1].progression.totalExperience, 125, "Never silently train a different individual")
        XCTAssertEqual(store.state.eggUsage, 100_000)
        XCTAssertEqual(store.rareCandyCount, 1)
    }

    func testNewerLocalSidecarProgressSurvivesOlderCompanionSave() throws {
        let (store, _) = try store(ownedState())
        let newer = PokemonProgression(totalExperience: 8_000, evs: [.speed: 20])
        let held = TradePokemon(creatureID: "trainee", speciesID: 25, baseID: 25, chainOrder: [25],
                                rarity: .common, isShiny: false, nature: nil, caughtAt: nil,
                                displayName: "Pikachu", originalTrainer: OriginalTrainer(trainerID: "me", trainerName: "Me"),
                                progression: newer)
        store.syncTrainingOwnership(held: [held], received: [], transferredIDs: [])
        XCTAssertEqual(store.trainingPokemon?.progression, newer)
        store.setTrainingTarget("trainee")
        store.setTrainingTarget("not-owned")
        XCTAssertEqual(store.trainingTargetID, "trainee")
        store.setTrainingExcludedIDs(["trainee"])
        XCTAssertEqual(store.trainedVersion(held), held)
    }

    func testChoosingBalancedPinsVisibleTraineeWhenAnotherPokemonHatches() async throws {
        let (store, _) = try store(ownedState())
        store.setTrainingMode(.balanced)
        XCTAssertEqual(store.trainingTargetID, "trainee")
        await store.hatch(baseID: 25)
        XCTAssertEqual(store.trainingTargetID, "trainee")
        store.routeGameplayTokens(200_000)
        XCTAssertEqual(store.state.dex[0].progression.totalEVs, 1)
        XCTAssertEqual(store.state.active?.progression.totalEVs, 0)
    }

    func testHugeCatchBankDrainsInBoundedBatchesWithoutLosingTokens() async throws {
        var state = CompanionState()
        let cycle = PokemonBalance.eggHatchThreshold + PokemonBalance.graduationTotal(.common)
        state.eggUsage = cycle * 20
        let (store, _) = try store(state)
        await store.hatchIfNeeded()
        for _ in 0..<200 {
            if store.state.dex.count >= 4 && !store.isHatching { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(store.state.dex.count, 4)
        XCTAssertNil(store.state.active)
        XCTAssertEqual(store.state.eggUsage, cycle * 16)
        await store.hatchIfNeeded()
        XCTAssertEqual(store.state.dex.count, 4)
    }
}
