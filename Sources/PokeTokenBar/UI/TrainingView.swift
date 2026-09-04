import SwiftUI

/// Compact progression readout shared by the Training and owned-Pokémon surfaces.
/// The catching evolution cycle and level progression are deliberately shown as
/// separate pieces of information: level-ups do not evolve the companion.
@MainActor
struct ProgressionSummaryView: View {
    let progression: PokemonProgression
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Lv. \(progression.level)")
                    .font(compact ? .callout.weight(.semibold) : .headline)
                Spacer(minLength: 0)
                Text("XP \(TokenFormatter.grouped(progression.totalExperience))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let needed = progression.experienceToNextLevel {
                HStack(spacing: 6) {
                    ProgressView(value: levelProgress)
                        .controlSize(.small)
                        .tint(.orange)
                    Text("\(TokenFormatter.compact(needed)) to next")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            } else {
                Text("Max level")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text("EVs")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text("\(progression.totalEVs)/\(PokemonProgression.maxTotalEVs)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(PokemonStat.allCases, id: \.rawValue) { stat in
                    HStack(spacing: 4) {
                        Text(statLabel(stat))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(progression.evs[stat] ?? 0)")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .padding(compact ? 8 : 10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private var levelProgress: Double {
        guard progression.level < PokemonProgression.maxLevel else { return 1 }
        let level = max(1, progression.level)
        let lowerBound = level * level * level
        let nextLevel = level + 1
        let upperBound = nextLevel * nextLevel * nextLevel
        let span = max(1, upperBound - lowerBound)
        return min(1, max(0, Double(progression.totalExperience - lowerBound) / Double(span)))
    }

    private func statLabel(_ stat: PokemonStat) -> String {
        switch stat {
        case .hp: return "HP"
        case .attack: return "Atk"
        case .defense: return "Def"
        case .specialAttack: return "Sp. Atk"
        case .specialDefense: return "Sp. Def"
        case .speed: return "Speed"
        }
    }
}

/// The gameplay mode surface stays intentionally small enough for the popover.
/// Catch remains the source of the egg/evolution/collection loop; Train only
/// improves the selected individual, and Balanced allocates exactly 50/50.
@MainActor
struct TrainingView: View {
    let store: CompanionStore
    @State private var confirmingCandy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                header
                if let error = store.persistenceError {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                modePicker

                if !store.trainingCandidates.isEmpty {
                    traineePicker
                    if let progression = store.trainingPokemon?.progression {
                        focusPicker
                        ProgressionSummaryView(progression: progression)
                    } else {
                        noTrainee
                    }
                } else {
                    noTrainee
                }

                candyCard
                rules
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 520)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Training", systemImage: "chart.bar.xaxis")
                .font(.callout.weight(.semibold))
            Spacer(minLength: 0)
            if let pokemon = store.trainingPokemon {
                Text("Lv. \(pokemon.progression.level)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: modeBinding) {
            Text("Catch").tag(TrainingMode.catching)
            Text("Train").tag(TrainingMode.training)
            Text("Balanced").tag(TrainingMode.balanced)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var traineePicker: some View {
        Picker("Trainee", selection: targetBinding) {
            Text("Choose a Pokémon").tag(String?.none).disabled(true)
            ForEach(store.trainingCandidates) { candidate in
                Text(candidateLabel(candidate)).tag(Optional(candidate.id))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var focusPicker: some View {
        Picker("EV focus", selection: focusBinding) {
            ForEach(PokemonStat.allCases, id: \.rawValue) { stat in
                Text(statLabel(stat)).tag(stat)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noTrainee: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.trainingCandidates.isEmpty ? "No trainee available yet" : "Selected trainee unavailable")
                .font(.callout.weight(.semibold))
            Text(noTraineeMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private var noTraineeMessage: String {
        if store.trainingCandidates.isEmpty {
            return "Tokens fall back to Catch until you own a Pokémon. Catch continues the egg → evolution → collection cycle."
        }
        return "This target is unavailable or trade-locked. Choose another Pokémon above; until then, tokens fall back to Catch."
    }

    private var candyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                ItemIconView(kind: .rareCandy, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rare Candy ×\(store.rareCandyCount)")
                        .font(.callout.weight(.semibold))
                    Text("+1 level · no EVs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if confirmingCandy {
                HStack(spacing: 8) {
                    Text("Raise the selected trainee by 1 level?")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Use") {
                        confirmingCandy = false
                        _ = store.useTrainingCandy()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Cancel") { confirmingCandy = false }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            } else {
                HStack {
                    Text(candyAvailabilityHint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Use Rare Candy") { confirmingCandy = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!store.canUseTrainingCandy)
                }
            }
        }
        .padding(9)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private var candyAvailabilityHint: String {
        if store.rareCandyCount == 0 { return "No Rare Candy available" }
        if store.trainingPokemon == nil { return "Choose a trainee first" }
        if store.trainingPokemon?.progression.level ?? 0 >= PokemonProgression.maxLevel {
            return "This trainee is at max level"
        }
        return "Selected trainee only"
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(modeExplanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Evolution stays in Catch mode; level-ups do not trigger canon-style evolution.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Rates: 1 XP / 1K tokens · 1 EV / 100K training tokens · EV caps: 252/stat · 510 total.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Legacy saves start at Lv. 5.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 1)
    }

    private var modeExplanation: String {
        if store.trainingPokemon == nil {
            return "Fallback: Catch. There is no trainee to receive training tokens."
        }
        switch store.trainingMode {
        case .catching:
            return "Catch sends all tokens through the egg → evolution → collection cycle."
        case .training:
            return "Train sends all tokens to the selected Pokémon for XP and the chosen EV focus."
        case .balanced:
            return "Balanced splits tokens exactly 50/50 between Catch and Train."
        }
    }

    private var modeBinding: Binding<TrainingMode> {
        Binding(get: { store.trainingMode }, set: { store.setTrainingMode($0) })
    }

    private var targetBinding: Binding<String?> {
        Binding(
            get: {
                let id = store.trainingTargetID ?? store.trainingPokemon?.id
                guard let id, store.trainingCandidates.contains(where: { $0.id == id }) else {
                    return nil
                }
                return id
            },
            set: { store.setTrainingTarget($0) }
        )
    }

    private var focusBinding: Binding<PokemonStat> {
        Binding(get: { store.trainingFocus }, set: { store.setTrainingFocus($0) })
    }

    private func candidateLabel(_ candidate: DexEntry) -> String {
        let name = candidate.names?[candidate.finalID].flatMap { store.language.resolveName($0) }
            ?? "#\(candidate.finalID)"
        let shiny = candidate.isShiny ? " ✨" : ""
        return "\(name)\(shiny) · Lv. \(candidate.progression.level)"
    }

    private func statLabel(_ stat: PokemonStat) -> String {
        switch stat {
        case .hp: return "HP"
        case .attack: return "Attack"
        case .defense: return "Defense"
        case .specialAttack: return "Sp. Attack"
        case .specialDefense: return "Sp. Defense"
        case .speed: return "Speed"
        }
    }
}
