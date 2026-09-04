import XCTest
@testable import PokeTokenBar

final class CatchingBallTests: XCTestCase {
    func testCatalogUsesStableRawNamesAndHasNoMasterBall() {
        XCTAssertEqual(CatchingBall.allCases,
                       [.pokeBall, .quickBall, .greatBall, .luxuryBall, .ultraBall])
        XCTAssertEqual(CatchingBall.allCases.map(\.rawValue),
                       ["pokeBall", "quickBall", "greatBall", "luxuryBall", "ultraBall"])
        XCTAssertNil(CatchingBall(rawValue: "masterBall"))
    }

    func testPresentationAndSpriteNames() {
        XCTAssertEqual(CatchingBall.pokeBall.displayName, "Poké Ball")
        XCTAssertEqual(CatchingBall.quickBall.displayName, "Quick Ball")
        XCTAssertEqual(CatchingBall.greatBall.displayName, "Great Ball")
        XCTAssertEqual(CatchingBall.luxuryBall.displayName, "Luxury Ball")
        XCTAssertEqual(CatchingBall.ultraBall.displayName, "Ultra Ball")

        XCTAssertEqual(CatchingBall.allCases.map(\.spriteName),
                       ["poke-ball", "quick-ball", "great-ball", "luxury-ball", "ultra-ball"])
        XCTAssertTrue(CatchingBall.allCases.allSatisfy { !$0.effectDescription.isEmpty })
    }

    func testPricesAreAffordableAndSorted() {
        XCTAssertEqual(CatchingBall.allCases.map(\.price),
                       [1_000_000, 2_000_000, 3_000_000, 4_000_000, 6_000_000])
        XCTAssertEqual(CatchingBall.allCases.map(\.price),
                       CatchingBall.allCases.map(\.price).sorted())
    }

    func testHatchThresholdMultipliers() {
        let base = 5_000_000
        XCTAssertEqual(CatchingBall.pokeBall.hatchThreshold(base: base), 4_000_000)
        XCTAssertEqual(CatchingBall.quickBall.hatchThreshold(base: base), 2_000_000)
        XCTAssertEqual(CatchingBall.greatBall.hatchThreshold(base: base), base)
        XCTAssertEqual(CatchingBall.luxuryBall.hatchThreshold(base: base), base)
        XCTAssertEqual(CatchingBall.ultraBall.hatchThreshold(base: base), base)
    }

    func testWeightMultiplierUsesOnlyCaptureRateBackedRareBand() {
        XCTAssertEqual(CatchingBall.pokeBall.weightMultiplier(captureRate: 3), 1)
        XCTAssertEqual(CatchingBall.greatBall.weightMultiplier(captureRate: 45), 2)
        XCTAssertEqual(CatchingBall.greatBall.weightMultiplier(captureRate: 46), 1)
        XCTAssertEqual(CatchingBall.ultraBall.weightMultiplier(captureRate: 30), 4)
        XCTAssertEqual(CatchingBall.luxuryBall.weightMultiplier(captureRate: 3), 1)

        XCTAssertEqual(CatchingBall.greatBall.maximumWeightMultiplier, 2)
        XCTAssertEqual(CatchingBall.ultraBall.maximumWeightMultiplier, 4)
        XCTAssertEqual(CatchingBall.quickBall.maximumWeightMultiplier, 1)
    }

    func testRarityWeightHelperPreservesCommonWeight() {
        XCTAssertEqual(CatchingBall.greatBall.rarityWeight(from: 7, isRare: false), 7)
        XCTAssertEqual(CatchingBall.greatBall.rarityWeight(from: 7, isRare: true), 14)
        XCTAssertEqual(CatchingBall.ultraBall.rarityWeight(from: 7, isRare: true), 28)
        XCTAssertEqual(CatchingBall.pokeBall.rarityWeight(from: 7, isRare: true), 7)
    }

    func testLuxuryBallOnlyAddsStartingExperience() {
        XCTAssertEqual(CatchingBall.luxuryBall.startingExperienceBonus, 875)
        XCTAssertEqual(CatchingBall.luxuryBall.effectDescription, "Hatches at level 10 (no EVs)")
        XCTAssertEqual(CatchingBall.pokeBall.startingExperienceBonus, 0)
        XCTAssertEqual(CatchingBall.greatBall.startingExperienceBonus, 0)
        XCTAssertEqual(CatchingBall.ultraBall.startingExperienceBonus, 0)
    }

    func testEffectArithmeticSaturatesBeforeConvertingToInt() {
        let extreme = CatchingBall.HatchEffect(hatchThresholdMultiplier: 2,
                                                rarityWeightMultiplier: Int.max,
                                                startingExperienceBonus: 0)
        XCTAssertEqual(extreme.hatchThreshold(base: Int.max), Int.max)
        XCTAssertEqual(extreme.rarityWeight(from: Int.max, isRare: true), Int.max)
    }

    func testFreeHatchEffectIsNeutral() {
        let free = CatchingBall.freeHatchEffect
        XCTAssertEqual(free.hatchThreshold(base: 5_000_000), 5_000_000)
        XCTAssertEqual(free.rarityWeight(from: 7, isRare: true), 7)
        XCTAssertEqual(free.startingExperienceBonus, 0)
    }

    func testBallAndEffectAreCodableSnapshots() throws {
        let ball = CatchingBall.ultraBall
        let encodedBall = try JSONEncoder().encode(ball)
        XCTAssertEqual(try JSONDecoder().decode(CatchingBall.self, from: encodedBall), ball)

        let snapshot = ball.hatchEffect
        let encodedEffect = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(CatchingBall.HatchEffect.self, from: encodedEffect),
                       snapshot)
    }
}
