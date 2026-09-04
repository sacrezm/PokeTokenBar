import SwiftUI

/// An individual Pokémon's saved details, without inventing battle stats or provenance.
@MainActor
struct OwnedPokemonDetailView: View {
    let pokemon: OwnedCollection.Pokemon
    let language: AppLanguage
    let onBack: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onBack) { Label("Owned Pokémon", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        SpriteView(speciesID: pokemon.speciesID, size: 80,
                                   animated: !reduceMotion, shiny: pokemon.isShiny)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pokemon.name).font(.headline)
                            Text("#\(pokemon.speciesID) · \(pokemon.generationLabel)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(L(language).rarityLabel(pokemon.rarity)) · \(pokemon.nature?.name(language) ?? "Nature unknown")\(pokemon.isShiny ? " · Shiny ✨" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ProgressionSummaryView(progression: pokemon.progression, compact: true)
                    Divider()
                    HStack {
                        Text(pokemon.isRaising ? "Raising now" : "In your collection")
                        Spacer()
                        if pokemon.isShiny { Image(systemName: "sparkles") }
                    }
                    .font(.callout).foregroundStyle(.secondary)
                    DisclosureGroup("History & identity") {
                        VStack(alignment: .leading, spacing: 14) {
                            detail("Original Trainer", pokemon.originalTrainerLabel)
                            detail("Recorded on", pokemon.recordedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not recorded")
                            Text("Collection record date, not necessarily the hatch or trade date.")
                                .font(.caption2).foregroundStyle(.secondary)
                            if !pokemon.isRaising {
                                detail("Pokémon ID", pokemon.id)
                                if let trainerID = pokemon.originalTrainerID {
                                    detail("Original Trainer ID", trainerID)
                                }
                            }
                        }
                        .padding(.top, 12)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
