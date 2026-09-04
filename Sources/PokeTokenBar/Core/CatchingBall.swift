import Foundation

/// Optional one-cycle hatch modifiers. No paid ball means `freeHatchEffect`.
///
/// These are app-specific gameplay effects, not canonical Pokémon catch formulas.
enum CatchingBall: String, Codable, CaseIterable, Sendable {
    // Keep the catalog in shop-price order.
    case pokeBall
    case quickBall
    case greatBall
    case luxuryBall
    case ultraBall

    /// Immutable values copied when a ball is equipped to the next egg.
    struct HatchEffect: Codable, Equatable, Sendable {
        let hatchThresholdMultiplier: Double
        let rarityWeightMultiplier: Int
        let startingExperienceBonus: Int

        init(hatchThresholdMultiplier: Double, rarityWeightMultiplier: Int,
             startingExperienceBonus: Int) {
            self.hatchThresholdMultiplier = hatchThresholdMultiplier
            self.rarityWeightMultiplier = rarityWeightMultiplier
            self.startingExperienceBonus = startingExperienceBonus
        }

        /// Applies the incubation multiplier to the normal egg threshold.
        func hatchThreshold(base baseThreshold: Int) -> Int {
            guard baseThreshold > 0 else { return 0 }
            let scaled = (Double(baseThreshold) * hatchThresholdMultiplier).rounded()
            guard !scaled.isNaN else { return baseThreshold }
            guard scaled < Double(Int.max) else { return Int.max }
            guard scaled.isFinite else { return baseThreshold }
            return max(1, Int(max(0, scaled)))
        }

        /// Applies the rare-weight multiplier only when the caller has source-backed
        /// evidence that the candidate belongs to the rare band.
        func rarityWeight(from baseWeight: Int, isRare: Bool) -> Int {
            let base = max(0, baseWeight)
            guard isRare else { return base }
            let scaled = (Double(base) * Double(rarityWeightMultiplier)).rounded()
            guard !scaled.isNaN else { return base }
            guard scaled < Double(Int.max) else { return Int.max }
            guard scaled.isFinite else { return base }
            return Int(max(0, scaled))
        }
    }

    /// The free/default hatch path. It must be used when no consumable is equipped.
    static let freeHatchEffect = HatchEffect(hatchThresholdMultiplier: 1.0,
                                             rarityWeightMultiplier: 1,
                                             startingExperienceBonus: 0)

    var displayName: String {
        switch self {
        case .pokeBall: return "Poké Ball"
        case .quickBall: return "Quick Ball"
        case .greatBall: return "Great Ball"
        case .luxuryBall: return "Luxury Ball"
        case .ultraBall: return "Ultra Ball"
        }
    }

    var price: Int {
        switch self {
        case .pokeBall: return 1_000_000
        case .quickBall: return 2_000_000
        case .greatBall: return 3_000_000
        case .luxuryBall: return 4_000_000
        case .ultraBall: return 6_000_000
        }
    }

    /// PokéAPI item sprite name. Assets remain runtime-loaded by the existing UI layer.
    var spriteName: String {
        switch self {
        case .pokeBall: return "poke-ball"
        case .quickBall: return "quick-ball"
        case .greatBall: return "great-ball"
        case .luxuryBall: return "luxury-ball"
        case .ultraBall: return "ultra-ball"
        }
    }

    var effectDescription: String {
        switch self {
        case .pokeBall: return "20% less incubation tokens"
        case .quickBall: return "60% less incubation tokens"
        case .greatBall: return "2× rare-or-better hatch weight"
        case .luxuryBall: return "Hatches at level 10 (no EVs)"
        case .ultraBall: return "4× rare-or-better hatch weight"
        }
    }

    var hatchEffect: HatchEffect {
        switch self {
        case .pokeBall:
            return HatchEffect(hatchThresholdMultiplier: 0.80,
                               rarityWeightMultiplier: 1,
                               startingExperienceBonus: 0)
        case .quickBall:
            return HatchEffect(hatchThresholdMultiplier: 0.40,
                               rarityWeightMultiplier: 1,
                               startingExperienceBonus: 0)
        case .greatBall:
            return HatchEffect(hatchThresholdMultiplier: 1.0,
                               rarityWeightMultiplier: 2,
                               startingExperienceBonus: 0)
        case .luxuryBall:
            return HatchEffect(hatchThresholdMultiplier: 1.0,
                               rarityWeightMultiplier: 1,
                               startingExperienceBonus: 875)
        case .ultraBall:
            return HatchEffect(hatchThresholdMultiplier: 1.0,
                               rarityWeightMultiplier: 4,
                               startingExperienceBonus: 0)
        }
    }

    var hatchThresholdMultiplier: Double { hatchEffect.hatchThresholdMultiplier }
    var rarityWeightMultiplier: Int { hatchEffect.rarityWeightMultiplier }
    var startingExperienceBonus: Int { hatchEffect.startingExperienceBonus }
    var maximumWeightMultiplier: Int { max(1, rarityWeightMultiplier) }

    func hatchThreshold(base baseThreshold: Int) -> Int {
        hatchEffect.hatchThreshold(base: baseThreshold)
    }

    /// Returns the multiplier for a capture-rate-backed rare candidate. The existing
    /// app classifies capture rates up to 45 as rare-or-better; no type lure is implied.
    func weightMultiplier(captureRate: Int) -> Int {
        rarityWeightMultiplier > 1 && captureRate <= 45 ? rarityWeightMultiplier : 1
    }

    func rarityWeight(from baseWeight: Int, isRare: Bool) -> Int {
        hatchEffect.rarityWeight(from: baseWeight, isRare: isRare)
    }
}
