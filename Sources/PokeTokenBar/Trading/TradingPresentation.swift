import Foundation

/// Collection is a read-only projection; a trade never rewrites hatch history.
enum TradingCollectionProjection {
    static func species(original: [CompanionStore.DexSpecies], received: [TradePokemon]) -> [CompanionStore.DexSpecies] {
        var result = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0) })
        for pokemon in received {
            let old = result[pokemon.speciesID]
            result[pokemon.speciesID] = CompanionStore.DexSpecies(
                id: pokemon.speciesID, name: old?.name ?? pokemon.displayName,
                rarity: old?.rarity ?? pokemon.rarity,
                isShiny: (old?.isShiny ?? false) || pokemon.isShiny,
                isRaising: old?.isRaising ?? false)
        }
        return result.values.sorted { $0.id < $1.id }
    }
}

struct TradingActivity: Equatable, Sendable {
    let id: String
    let title: String
    let body: String
}
