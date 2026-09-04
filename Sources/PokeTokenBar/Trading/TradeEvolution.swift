import Foundation

/// Gen 1–5 trade rules that need no held-item system. Kept local so receipt
/// recovery works offline and never depends on a second server transaction.
/// Source: https://github.com/PokeAPI/pokeapi/blob/master/data/v2/csv/pokemon_evolution.csv
enum TradeEvolution {
    private struct Rule {
        let species: Int
        let name: String
        let partner: Int?
        init(_ species: Int, _ name: String, partner: Int? = nil) {
            self.species = species
            self.name = name
            self.partner = partner
        }
    }

    private static let rules: [Int: Rule] = [
        64: Rule(65, "Alakazam"), 67: Rule(68, "Machamp"),
        75: Rule(76, "Golem"), 93: Rule(94, "Gengar"),
        525: Rule(526, "Gigalith"), 533: Rule(534, "Conkeldurr"),
        588: Rule(589, "Escavalier", partner: 616),
        616: Rule(617, "Accelgor", partner: 588),
    ]

    static func received(_ pokemon: TradePokemon, exchangedFor species: Int) -> TradePokemon {
        guard let rule = rules[pokemon.speciesID], rule.partner == nil || rule.partner == species else {
            return pokemon
        }
        var chain = pokemon.chainOrder
        if !chain.contains(pokemon.speciesID) { chain.append(pokemon.speciesID) }
        if !chain.contains(rule.species) { chain.append(rule.species) }
        return TradePokemon(creatureID: pokemon.creatureID, speciesID: rule.species,
                            baseID: pokemon.baseID, chainOrder: chain, rarity: pokemon.rarity,
                            isShiny: pokemon.isShiny, nature: pokemon.nature, caughtAt: pokemon.caughtAt,
                            displayName: rule.name, originalTrainer: pokemon.originalTrainer,
                            progression: pokemon.progression)
    }

    /// A previously received individual may return after evolving on another Mac.
    /// Do not mistake that legitimate species change for a duplicate identity.
    static func isReturning(_ incoming: TradePokemon, previously received: TradePokemon) -> Bool {
        incoming.creatureID == received.creatureID
            && incoming.originalTrainer == received.originalTrainer
            && incoming.baseID == received.baseID && incoming.caughtAt == received.caughtAt
            && incoming.isShiny == received.isShiny && incoming.nature == received.nature
            && incoming.rarity == received.rarity
            && (incoming.speciesID == received.speciesID || rules[received.speciesID]?.species == incoming.speciesID)
    }
}
