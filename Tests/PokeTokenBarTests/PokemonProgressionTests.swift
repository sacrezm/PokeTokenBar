import XCTest
@testable import PokeTokenBar

final class PokemonProgressionTests: XCTestCase {
    func testDefaultStartsAtLevelFiveAndUsesCubicThresholds() {
        let starter = PokemonProgression()

        XCTAssertEqual(starter.totalExperience, 125)
        XCTAssertEqual(starter.level, 5)
        XCTAssertEqual(PokemonProgression(totalExperience: 215).level, 5)
        XCTAssertEqual(PokemonProgression(totalExperience: 216).level, 6)
        XCTAssertEqual(PokemonProgression(totalExperience: 342).level, 6)
        XCTAssertEqual(PokemonProgression(totalExperience: 343).level, 7)
        XCTAssertEqual(PokemonProgression(totalExperience: 1_000_000).level, 100)
        XCTAssertEqual(PokemonProgression(totalExperience: Int.max).level, 100)
    }

    func testTrainingModesAllocateEveryTokenAndAlternateBalancedOddToken() {
        XCTAssertEqual(TrainingMode.catching.rawValue, "catching")
        XCTAssertEqual(TrainingMode.training.rawValue, "training")
        XCTAssertEqual(TrainingMode.balanced.rawValue, "balanced")
        XCTAssertEqual(TrainingMode.catching.displayName, "Catch")
        XCTAssertTrue(TrainingMode.training.details.contains("paused"))

        var remainder = 0
        let first = TrainingMode.balanced.allocate(tokens: 3, remainder: &remainder)
        XCTAssertEqual(first.catching, 2)
        XCTAssertEqual(first.training, 1)
        XCTAssertEqual(first.catching + first.training, 3)
        XCTAssertEqual(remainder, 1)

        let second = TrainingMode.balanced.allocate(tokens: 3, remainder: &remainder)
        XCTAssertEqual(second.catching, 1)
        XCTAssertEqual(second.training, 2)
        XCTAssertEqual(second.catching + second.training, 3)
        XCTAssertEqual(remainder, 0)

        let negative = TrainingMode.training.allocate(tokens: -9, remainder: &remainder)
        XCTAssertEqual(negative.catching, 0)
        XCTAssertEqual(negative.training, 0)
        XCTAssertEqual(remainder, 0)
    }

    func testCatchExperienceUsesPersistentRemainderAndNeverAddsEVs() {
        var progression = PokemonProgression()

        XCTAssertEqual(progression.gainExperience(tokens: 999), 0)
        XCTAssertEqual(progression.experienceRemainder, 999)
        XCTAssertEqual(progression.gainExperience(tokens: 1), 1)
        XCTAssertEqual(progression.totalExperience, 126)
        XCTAssertEqual(progression.evs.values.reduce(0, +), 0)
    }

    func testTrainingCarriesXPAndFocusedEVTokensIndependently() {
        var progression = PokemonProgression()

        let first = progression.gainTraining(tokens: 999, focus: .attack)
        XCTAssertEqual(first.experienceGained, 0)
        XCTAssertEqual(first.evsGained, [:])
        XCTAssertEqual(progression.experienceRemainder, 999)
        XCTAssertEqual(progression.trainingRemainder, 999)

        let second = progression.gainTraining(tokens: 99_001, focus: .attack)
        XCTAssertEqual(second.experienceGained, 100)
        XCTAssertEqual(second.evsGained[.attack], 1)
        XCTAssertEqual(progression.totalExperience, 225)
        XCTAssertEqual(progression.ev(for: .attack), 1)
        XCTAssertEqual(progression.trainingRemainder, 0)
        XCTAssertEqual(second.levelBefore, 5)
        XCTAssertEqual(second.levelAfter, 6)
        XCTAssertTrue(second.didLevelUp)
    }

    func testCatchTokensDoNotLeakIntoTrainingEVCarry() {
        var progression = PokemonProgression()

        _ = progression.gainExperience(tokens: 50_000)
        _ = progression.gainTraining(tokens: 50_000, focus: .speed)
        XCTAssertEqual(progression.ev(for: .speed), 0)
        XCTAssertEqual(progression.trainingRemainder, 50_000)

        _ = progression.gainTraining(tokens: 50_000, focus: .speed)
        XCTAssertEqual(progression.ev(for: .speed), 1)
    }

    func testEVCapsProtectBothPerStatAndTotalLimits() {
        var perStat = PokemonProgression(evs: [.hp: 251])
        let gain = perStat.gainTraining(tokens: 200_000, focus: .hp)
        XCTAssertEqual(gain.evsGained[.hp], 1)
        XCTAssertEqual(perStat.ev(for: .hp), 252)
        XCTAssertEqual(perStat.totalEVs, 252)

        var total = PokemonProgression(evs: [.hp: 252, .attack: 252, .defense: 6])
        let blocked = total.gainTraining(tokens: 100_000, focus: .speed)
        XCTAssertEqual(blocked.evsGained, [:])
        XCTAssertEqual(total.totalEVs, 510)
        XCTAssertEqual(total.ev(for: .speed), 0)
    }

    func testRareCandyAdvancesExactlyOneLevelWithoutChangingOtherState() {
        var progression = PokemonProgression(
            totalExperience: 200,
            evs: [.specialDefense: 4],
            trainingRemainder: 42,
            experienceRemainder: 7
        )

        XCTAssertTrue(progression.useRareCandy())
        XCTAssertEqual(progression.level, 6)
        XCTAssertEqual(progression.totalExperience, 216)
        XCTAssertEqual(progression.ev(for: .specialDefense), 4)
        XCTAssertEqual(progression.trainingRemainder, 42)
        XCTAssertEqual(progression.experienceRemainder, 7)

        XCTAssertTrue(progression.useRareCandy())
        XCTAssertEqual(progression.level, 7)
        XCTAssertEqual(progression.totalExperience, 343)

        var maxed = PokemonProgression(totalExperience: PokemonProgression.maxExperience)
        XCTAssertFalse(maxed.canUseRareCandy)
        XCTAssertFalse(maxed.useRareCandy())
        XCTAssertEqual(maxed.totalExperience, PokemonProgression.maxExperience)
    }

    func testCodableDefaultsMigrationAndRoundTripAreSafe() throws {
        let legacy = #"{"totalExperience":216,"evs":{"attack":7},"trainingRemainder":42}"#
        let decoded = try JSONDecoder().decode(PokemonProgression.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.level, 6)
        XCTAssertEqual(decoded.ev(for: .attack), 7)
        XCTAssertEqual(decoded.ev(for: .hp), 0)
        XCTAssertEqual(decoded.trainingRemainder, 42)
        XCTAssertEqual(decoded.experienceRemainder, 0)

        let roundTrip = try JSONDecoder().decode(
            PokemonProgression.self,
            from: JSONEncoder().encode(decoded)
        )
        XCTAssertEqual(roundTrip, decoded)

        let invalid = #"{"totalExperience":-10,"evs":{"hp":999,"attack":-4},"trainingRemainder":999999,"unknown":true}"#
        let sanitized = try JSONDecoder().decode(PokemonProgression.self, from: Data(invalid.utf8))
        XCTAssertEqual(sanitized.totalExperience, PokemonProgression.startingExperience)
        XCTAssertEqual(sanitized.ev(for: .hp), 252)
        XCTAssertEqual(sanitized.ev(for: .attack), 0)
        XCTAssertEqual(sanitized.trainingRemainder, 99_999)
    }
}
