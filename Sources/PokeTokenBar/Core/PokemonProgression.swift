import Foundation

/// The six battle-relevant effort-value buckets.
enum PokemonStat: String, Codable, CaseIterable, Sendable {
    case hp
    case attack
    case defense
    case specialAttack = "special-attack"
    case specialDefense = "special-defense"
    case speed

    var displayName: String {
        switch self {
        case .hp: "HP"
        case .attack: "Attack"
        case .defense: "Defense"
        case .specialAttack: "Special Attack"
        case .specialDefense: "Special Defense"
        case .speed: "Speed"
        }
    }
}

/// How usage is divided between the existing catch/evolution loop and training.
/// The raw values are storage identifiers; `catch` is a Swift keyword, so the
/// identifier is intentionally `catching`.
enum TrainingMode: String, Codable, CaseIterable, Sendable {
    case catching
    case training
    case balanced

    var displayName: String {
        switch self {
        case .catching: "Catch"
        case .training: "Train"
        case .balanced: "Balanced"
        }
    }

    var details: String {
        switch self {
        case .catching:
            "Catch advances the collection cycle and grants XP; EVs stay unchanged."
        case .training:
            "Train grants XP and focused EVs; collection evolution is paused."
        case .balanced:
            "Split usage between catching and training; odd tokens alternate sides."
        }
    }

    /// Allocates every nonnegative token exactly once. `remainder` is a small
    /// fairness marker for the odd token in balanced mode: 0 gives the next
    /// odd token to catching, 1 gives it to training. It is safe to persist it
    /// alongside the owner's state.
    func allocate(tokens: Int, remainder: inout Int) -> (catching: Int, training: Int) {
        let amount = max(0, tokens)
        switch self {
        case .catching:
            remainder = 0
            return (amount, 0)
        case .training:
            remainder = 0
            return (0, amount)
        case .balanced:
            let half = amount / 2
            guard amount % 2 == 1 else { return (half, half) }

            if remainder == 0 {
                remainder = 1
                return (half + 1, half)
            } else {
                remainder = 0
                return (half, half + 1)
            }
        }
    }
}

/// The observable result of one focused training operation.
struct TrainingGain: Codable, Equatable, Sendable {
    let tokens: Int
    let experienceGained: Int
    let evsGained: [PokemonStat: Int]
    let levelBefore: Int
    let levelAfter: Int

    var didLevelUp: Bool { levelAfter > levelBefore }
}

/// Compact, local progression state for one individual Pokémon.
///
/// XP is an absolute total and level is derived from `level^3`. Catch usage
/// calls `gainExperience(tokens:)`; focused training calls `gainTraining` and
/// additionally earns EVs. No method resets the state, so a graduated
/// individual can carry the same progression forward.
struct PokemonProgression: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let startingLevel = 5
    static let maxLevel = 100
    static let startingExperience = startingLevel * startingLevel * startingLevel
    static let maxExperience = maxLevel * maxLevel * maxLevel
    static let tokensPerExperience = 1_000
    static let tokensPerEV = 100_000
    static let maxEVPerStat = 252
    static let maxTotalEVs = 510

    var totalExperience: Int {
        didSet { totalExperience = Self.clampExperience(totalExperience) }
    }

    /// Always contains all six stats, including zero-valued stats.
    var evs: [PokemonStat: Int] {
        didSet { evs = Self.normalizedEVs(evs) }
    }

    /// XP carry shared by catching and training. Always less than 1,000.
    var experienceRemainder: Int {
        didSet { experienceRemainder = Self.normalizedRemainder(experienceRemainder, modulus: Self.tokensPerExperience) }
    }

    /// Focused-training carry used only for EVs. Always less than 100,000.
    var trainingRemainder: Int {
        didSet { trainingRemainder = Self.normalizedRemainder(trainingRemainder, modulus: Self.tokensPerEV) }
    }

    init(
        totalExperience: Int = Self.startingExperience,
        evs: [PokemonStat: Int] = [:],
        trainingRemainder: Int = 0,
        experienceRemainder: Int = 0
    ) {
        self.totalExperience = Self.clampExperience(totalExperience)
        self.evs = Self.normalizedEVs(evs)
        self.trainingRemainder = Self.normalizedRemainder(trainingRemainder, modulus: Self.tokensPerEV)
        self.experienceRemainder = Self.normalizedRemainder(experienceRemainder, modulus: Self.tokensPerExperience)
    }

    var level: Int { Self.level(forExperience: totalExperience) }

    var totalEVs: Int { evs.values.reduce(0, +) }

    var isMaxLevel: Bool { level >= Self.maxLevel }

    var canUseRareCandy: Bool { !isMaxLevel }

    var experienceToNextLevel: Int? {
        guard !isMaxLevel else { return nil }
        return Self.experience(forLevel: level + 1) - totalExperience
    }

    func ev(for stat: PokemonStat) -> Int { evs[stat] ?? 0 }

    /// Absolute XP threshold for a level, clamped to the supported range.
    static func experience(forLevel level: Int) -> Int {
        let bounded = min(max(level, startingLevel), maxLevel)
        return bounded * bounded * bounded
    }

    /// Derives a level using integer arithmetic, avoiding floating-point cube-root edges.
    static func level(forExperience experience: Int) -> Int {
        let bounded = clampExperience(experience)
        var lower = startingLevel
        var upper = maxLevel
        while lower < upper {
            let candidate = (lower + upper + 1) / 2
            if Self.experience(forLevel: candidate) <= bounded {
                lower = candidate
            } else {
                upper = candidate - 1
            }
        }
        return lower
    }

    /// Grants one XP for each 1,000 usage tokens, carrying sub-threshold tokens.
    /// This is the catch-path helper and never changes EVs.
    @discardableResult
    mutating func gainExperience(tokens: Int) -> Int {
        let amount = max(0, tokens)
        guard amount > 0 else { return 0 }

        let whole = amount / Self.tokensPerExperience
        let partial = amount % Self.tokensPerExperience
        let combined = experienceRemainder + partial
        let carriedWhole = combined / Self.tokensPerExperience
        experienceRemainder = combined % Self.tokensPerExperience

        let earned = whole + carriedWhole
        let available = Self.maxExperience - totalExperience
        let applied = min(earned, available)
        totalExperience += applied
        return applied
    }

    /// Grants XP and, when focused, one EV for each 100,000 training tokens.
    /// A nil focus is intentional XP-only usage (the catch path).
    @discardableResult
    mutating func gainTraining(tokens: Int, focus: PokemonStat? = nil) -> TrainingGain {
        let amount = max(0, tokens)
        let levelBefore = level
        let experienceGained = gainExperience(tokens: amount)
        var evsGained: [PokemonStat: Int] = [:]

        if let focus, amount > 0 {
            let whole = amount / Self.tokensPerEV
            let partial = amount % Self.tokensPerEV
            let combined = trainingRemainder + partial
            let earned = whole + combined / Self.tokensPerEV
            trainingRemainder = combined % Self.tokensPerEV

            let statCapacity = Self.maxEVPerStat - ev(for: focus)
            let totalCapacity = Self.maxTotalEVs - totalEVs
            let applied = min(earned, max(0, min(statCapacity, totalCapacity)))
            if applied > 0 {
                evs[focus, default: 0] += applied
                evs = Self.normalizedEVs(evs)
                evsGained[focus] = applied
            }
        }

        return TrainingGain(
            tokens: amount,
            experienceGained: experienceGained,
            evsGained: evsGained,
            levelBefore: levelBefore,
            levelAfter: level
        )
    }

    /// A Rare Candy advances exactly one derived level, without injecting a
    /// legacy token burst or changing either persistent carry.
    @discardableResult
    mutating func useRareCandy() -> Bool {
        guard canUseRareCandy else { return false }
        totalExperience = Self.experience(forLevel: level + 1)
        return true
    }

    private static func clampExperience(_ value: Int) -> Int {
        min(max(value, startingExperience), maxExperience)
    }

    private static func normalizedRemainder(_ value: Int, modulus: Int) -> Int {
        guard modulus > 0 else { return 0 }
        return max(0, value) % modulus
    }

    private static func normalizedEVs(_ values: [PokemonStat: Int]) -> [PokemonStat: Int] {
        var normalized = Dictionary(uniqueKeysWithValues: PokemonStat.allCases.map { ($0, 0) })
        var remaining = maxTotalEVs
        for stat in PokemonStat.allCases {
            let requested = min(max(values[stat] ?? 0, 0), maxEVPerStat)
            let applied = min(requested, remaining)
            normalized[stat] = applied
            remaining -= applied
        }
        return normalized
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case totalExperience
        case experience
        case xp
        case evs
        case experienceRemainder
        case xpRemainder
        case trainingRemainder
        case trainingCarry
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let totalExperience = Self.decodeInt(
            from: container,
            keys: [.totalExperience, .experience, .xp],
            default: Self.startingExperience
        )
        let experienceRemainder = Self.decodeInt(
            from: container,
            keys: [.experienceRemainder, .xpRemainder],
            default: 0
        )
        let trainingRemainder = Self.decodeInt(
            from: container,
            keys: [.trainingRemainder, .trainingCarry],
            default: 0
        )

        var decodedEVs: [PokemonStat: Int] = [:]
        if let raw = try? container.decode([String: Int].self, forKey: .evs) {
            for (key, value) in raw {
                if let stat = PokemonStat(rawValue: key) { decodedEVs[stat] = value }
            }
        } else if let raw = try? container.decode([PokemonStat: Int].self, forKey: .evs) {
            decodedEVs = raw
        }

        self.init(
            totalExperience: totalExperience,
            evs: decodedEVs,
            trainingRemainder: trainingRemainder,
            experienceRemainder: experienceRemainder
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(totalExperience, forKey: .totalExperience)
        let rawEVs = Dictionary(uniqueKeysWithValues: PokemonStat.allCases.map { ($0.rawValue, ev(for: $0)) })
        try container.encode(rawEVs, forKey: .evs)
        try container.encode(experienceRemainder, forKey: .experienceRemainder)
        try container.encode(trainingRemainder, forKey: .trainingRemainder)
    }

    private static func decodeInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys],
        default defaultValue: Int
    ) -> Int {
        for key in keys {
            if let value = try? container.decode(Int.self, forKey: key) { return value }
        }
        return defaultValue
    }
}
