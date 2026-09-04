import Foundation

/// Pure, deterministic game state for the optional Magikarp Flap mini-game.
/// Coordinates are normalized so the engine is independent of the SwiftUI layout.
struct MagikarpFlapGame: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case ready, running, gameOver }

    struct Gate: Equatable, Identifiable, Sendable {
        let id: Int
        var x: Double
        var gapCenter: Double
        var didScore = false
    }

    static let fishX = 0.24
    static let fishHalfWidth = 0.055
    static let fishHalfHeight = 0.05
    static let gateWidth = 0.16
    static let gateGap = 0.31
    static let gateSpacing = 0.68
    static let floor = 0.06
    static let ceiling = 0.96
    static let gravity = 1.75
    static let flapVelocity = 0.68
    static let scrollSpeed = 0.72

    private(set) var phase: Phase = .ready
    private(set) var fishY = 0.5
    private(set) var velocity = 0.0
    private(set) var score = 0
    var gates: [Gate]
    private var randomState: UInt64

    init(seed: UInt64 = 0x4D41_4749_4B41_5250) {
        randomState = seed == 0 ? 1 : seed
        gates = []
        for index in 0..<3 {
            gates.append(Gate(id: index, x: 1.05 + Double(index) * Self.gateSpacing,
                              gapCenter: Self.nextGap(using: &randomState)))
        }
    }

    mutating func flap() {
        if phase == .gameOver { resetRound() }
        phase = .running
        velocity = Self.flapVelocity
    }

    mutating func resetRound() {
        phase = .ready
        fishY = 0.5
        velocity = 0
        score = 0
        for index in gates.indices {
            gates[index].x = 1.05 + Double(index) * Self.gateSpacing
            gates[index].gapCenter = Self.nextGap(using: &randomState)
            gates[index].didScore = false
        }
    }

    mutating func tick(seconds rawSeconds: Double) {
        guard phase == .running else { return }
        let seconds = min(max(rawSeconds, 0), 0.05)
        velocity -= Self.gravity * seconds
        fishY += velocity * seconds

        for index in gates.indices {
            gates[index].x -= Self.scrollSpeed * seconds
            if !gates[index].didScore,
               gates[index].x + Self.gateWidth / 2 < Self.fishX - Self.fishHalfWidth {
                gates[index].didScore = true
                score += 1
            }
        }

        recyclePassedGates()
        if collides { phase = .gameOver }
    }

    var collides: Bool {
        if fishY - Self.fishHalfHeight <= Self.floor || fishY + Self.fishHalfHeight >= Self.ceiling {
            return true
        }
        for gate in gates {
            let overlapsHorizontally = Self.fishX + Self.fishHalfWidth >= gate.x - Self.gateWidth / 2 &&
                Self.fishX - Self.fishHalfWidth <= gate.x + Self.gateWidth / 2
            guard overlapsHorizontally else { continue }
            let lowerGap = gate.gapCenter - Self.gateGap / 2
            let upperGap = gate.gapCenter + Self.gateGap / 2
            if fishY - Self.fishHalfHeight <= lowerGap || fishY + Self.fishHalfHeight >= upperGap {
                return true
            }
        }
        return false
    }

    private mutating func recyclePassedGates() {
        guard let furthest = gates.map(\.x).max() else { return }
        var nextX = furthest
        for index in gates.indices where gates[index].x < -Self.gateWidth {
            nextX += Self.gateSpacing
            gates[index].x = nextX
            gates[index].gapCenter = Self.nextGap(using: &randomState)
            gates[index].didScore = false
        }
    }

    private static func nextGap(using state: inout UInt64) -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        let unit = Double(state & 0xFFFF) / Double(UInt16.max)
        return 0.34 + unit * 0.32
    }
}
