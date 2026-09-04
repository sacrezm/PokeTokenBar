import Foundation

/// Individuals currently owned, not the Pokédex's history of species seen.
/// The sidecar takes precedence for returned/evolved Pokémon with the same ID.
enum OwnedCollection {
    struct Pokemon: Identifiable, Equatable {
        let id: String
        let speciesID: Int
        let name: String
        let isShiny: Bool
        let isRaising: Bool
        let originalTrainer: String?
        let originalTrainerID: String?
        let rarity: Rarity
        let nature: PokemonNature?
        let recordedAt: Date?

        var originalTrainerLabel: String { originalTrainer ?? "Not recorded" }
        var generationLabel: String {
            HatchGeneration.allCases.first { $0.speciesIDs.contains(speciesID) }?.label ?? "Unknown"
        }
    }

    static func pokemon(entries: [DexEntry], activeID: String?, held: [TradePokemon],
                        transferredIDs: Set<String>, language: AppLanguage) -> [Pokemon] {
        var result: [String: Pokemon] = [:]
        for entry in entries where !entry.isReleased && !transferredIDs.contains(entry.id) {
            result[entry.id] = Pokemon(id: entry.id, speciesID: entry.finalID,
                                      name: entry.names?[entry.finalID].flatMap { language.resolveName($0) }
                                          ?? "#\(entry.finalID)",
                                      isShiny: entry.isShiny, isRaising: entry.id == activeID,
                                      originalTrainer: nil, originalTrainerID: nil,
                                      rarity: entry.rarity, nature: entry.nature, recordedAt: entry.caughtAt)
        }
        for pokemon in held {
            result[pokemon.creatureID] = Pokemon(id: pokemon.creatureID, speciesID: pokemon.speciesID,
                                                name: pokemon.displayName, isShiny: pokemon.isShiny,
                                                isRaising: false, originalTrainer: pokemon.originalTrainer.trainerName,
                                                originalTrainerID: pokemon.originalTrainer.trainerID,
                                                rarity: pokemon.rarity, nature: pokemon.nature,
                                                recordedAt: pokemon.caughtAt)
        }
        return result.values.sorted {
            if $0.isRaising != $1.isRaising { return $0.isRaising }
            if $0.speciesID != $1.speciesID { return $0.speciesID < $1.speciesID }
            return $0.id < $1.id
        }
    }
}
