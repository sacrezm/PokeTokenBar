import XCTest
import AppKit
import SwiftUI
@testable import PokeTokenBar

final class MagikarpFlapGameTests: XCTestCase {
    func testStartsReadyWithThreeGates() {
        let game = MagikarpFlapGame(seed: 1)
        XCTAssertEqual(game.phase, .ready)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.gates.count, 3)
        XCTAssertTrue(game.gates.allSatisfy { (0.34...0.66).contains($0.gapCenter) })
    }

    func testZeroSeedAndEmptyGateFieldAreSafe() {
        var game = MagikarpFlapGame(seed: 0)
        game.gates = []
        game.flap()
        game.tick(seconds: 0)
        XCTAssertEqual(game.phase, .running)
        XCTAssertTrue(game.fishY.isFinite)
    }

    func testFlapStartsTheRoundAndGravityPullsBackDown() {
        var game = MagikarpFlapGame(seed: 2)
        game.flap()
        XCTAssertEqual(game.phase, .running)
        XCTAssertEqual(game.velocity, MagikarpFlapGame.flapVelocity)

        let initialY = game.fishY
        game.tick(seconds: 0.05)
        XCTAssertGreaterThan(game.fishY, initialY)
        for _ in 0..<12 { game.tick(seconds: 0.05) }
        XCTAssertLessThan(game.velocity, 0)
    }

    func testGateScoresOnlyOnceAfterPassingTheFish() {
        var game = MagikarpFlapGame(seed: 3)
        game.gates = [MagikarpFlapGame.Gate(id: 1, x: 0.09, gapCenter: 0.5)]
        game.flap()
        game.tick(seconds: 0.05)
        XCTAssertEqual(game.score, 1)
        game.tick(seconds: 0.05)
        XCTAssertEqual(game.score, 1)
    }

    func testBoundaryAndGateCollisionsEndTheRound() {
        var boundary = MagikarpFlapGame(seed: 4)
        boundary.flap()
        for _ in 0..<100 where boundary.phase == .running { boundary.tick(seconds: 0.05) }
        XCTAssertEqual(boundary.phase, .gameOver)

        var gate = MagikarpFlapGame(seed: 5)
        gate.gates = [MagikarpFlapGame.Gate(id: 1, x: MagikarpFlapGame.fishX, gapCenter: 0.2)]
        gate.flap()
        gate.tick(seconds: 0)
        XCTAssertEqual(gate.phase, .gameOver)
    }

    func testFlapAfterGameOverStartsFreshRound() {
        var game = MagikarpFlapGame(seed: 6)
        game.flap()
        for _ in 0..<100 where game.phase == .running { game.tick(seconds: 0.05) }
        XCTAssertEqual(game.phase, .gameOver)
        game.flap()
        XCTAssertEqual(game.phase, .running)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.velocity, MagikarpFlapGame.flapVelocity)
    }

    func testSeededSimulationIsDeterministicAndFinite() {
        var first = MagikarpFlapGame(seed: 42)
        var second = MagikarpFlapGame(seed: 42)
        first.flap()
        second.flap()
        for step in 0..<10_000 {
            if step.isMultiple(of: 11) {
                first.flap()
                second.flap()
            }
            first.tick(seconds: 1 / 60)
            second.tick(seconds: 1 / 60)
        }
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.fishY.isFinite)
        XCTAssertTrue(first.gates.allSatisfy { $0.x.isFinite && $0.gapCenter.isFinite })
    }
}

@MainActor
final class MagikarpFlapLayoutTests: XCTestCase {
    func testGameFitsThePopoverContentWidthAndHeight() {
        let suite = "MagikarpFlapLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = NSHostingController(rootView:
            MagikarpFlapView(onClose: {}, defaults: defaults)
                .frame(width: PopoverMetrics.contentWidth)
        )
        let measured = controller.sizeThatFits(in: CGSize(width: PopoverMetrics.contentWidth,
                                                          height: .greatestFiniteMagnitude))
        XCTAssertLessThanOrEqual(measured.width, PopoverMetrics.contentWidth)
        XCTAssertLessThanOrEqual(measured.height, 520)
        XCTAssertGreaterThan(measured.height, 480)
    }
}
