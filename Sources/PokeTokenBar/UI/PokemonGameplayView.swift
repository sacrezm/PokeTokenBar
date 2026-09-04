import SwiftUI

/// Level progress first; detailed EV investment is available on demand.
@MainActor
struct ProgressionSummaryView: View {
    let progression: PokemonProgression
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Level \(progression.level)").font(.headline)
                    Spacer()
                    Text(progression.experienceToNextLevel.map { "\(TokenFormatter.grouped($0)) XP to next level" } ?? "Max level")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                ProgressView(value: levelProgress)
                    .controlSize(.small).tint(.orange)
                    .accessibilityLabel("Experience to next level")
            }
            DisclosureGroup {
                VStack(spacing: 8) {
                    ForEach(PokemonStat.allCases, id: \.rawValue) { stat in
                        HStack {
                            Text(stat.displayName).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(progression.evs[stat] ?? 0)").monospacedDigit()
                        }
                    }
                    Text("252 per stat · 510 total · \(TokenFormatter.grouped(progression.totalExperience)) total XP")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption).padding(.top, 10)
            } label: {
                HStack {
                    Text("Effort values")
                    Spacer()
                    Text("\(progression.totalEVs) / \(PokemonProgression.maxTotalEVs)").monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var levelProgress: Double {
        guard progression.level < PokemonProgression.maxLevel else { return 1 }
        let level = max(1, progression.level)
        let lower = level * level * level
        let next = level + 1
        return min(1, max(0, Double(progression.totalExperience - lower) / Double(max(1, next * next * next - lower))))
    }
}

@MainActor
struct PokemonGameplayView: View {
    let store: CompanionStore
    @State private var confirmingCandy = false
    @State private var showingHelp = false
    @State private var showingMagikarpFlap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if showingMagikarpFlap {
            MagikarpFlapView { showingMagikarpFlap = false }
        } else {
            gameplay
        }
    }

    private var gameplay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activity").font(.title3.weight(.semibold))
                        Spacer()
                        Picker("Token allocation", selection: modeBinding) {
                            ForEach(TrainingMode.allCases, id: \.rawValue) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                        Button { showingHelp.toggle() } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("How catching and training work")
                        .popover(isPresented: $showingHelp) { rules.padding(18).frame(width: 290) }
                    }
                    Text(modeExplanation).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = store.persistenceError {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if store.trainingMode != .training || store.trainingPokemon == nil {
                    CompanionHeader(store: store)
                    if store.trainingMode == .balanced { Divider() }
                }
                if store.trainingMode != .catching {
                    if !store.trainingCandidates.isEmpty {
                        HStack(spacing: 14) {
                            if let pokemon = store.trainingPokemon {
                                SpriteView(speciesID: pokemon.finalID, size: 64,
                                           animated: !reduceMotion, shiny: pokemon.isShiny)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Training Pokémon").font(.caption).foregroundStyle(.secondary)
                                Picker("Training Pokémon", selection: targetBinding) {
                                    Text("Choose a Pokémon").tag(String?.none).disabled(true)
                                    ForEach(store.trainingCandidates) { candidate in
                                        Text(candidateLabel(candidate)).tag(Optional(candidate.id))
                                    }
                                }
                                .labelsHidden().pickerStyle(.menu)
                            }
                        }
                    }
                    if let progression = store.trainingPokemon?.progression {
                        ProgressionSummaryView(progression: progression)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Train a stat").font(.callout)
                                Text("\(progression.evs[store.trainingFocus] ?? 0) / 252 EVs")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("EV focus", selection: focusBinding) {
                                ForEach(PokemonStat.allCases, id: \.rawValue) { stat in
                                    Text(stat.displayName).tag(stat)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                        Divider()
                        candyAction
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No available trainee").font(.headline)
                            Text("Choose an owned Pokémon that isn't trade-locked. Until then, all tokens go to Catch.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button {
                        showingMagikarpFlap = true
                    } label: {
                        Label("Magikarp Flap", systemImage: "gamecontroller.fill")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Play a score-only mini-game. It does not affect Pokémon progress or tokens.")
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 520)
        .onChange(of: store.trainingPokemon?.id) { confirmingCandy = false }
    }

    private var candyAction: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ItemIconView(kind: .rareCandy, size: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rare Candy").font(.callout)
                    Text("\(store.rareCandyCount) available · +1 level")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !confirmingCandy {
                    Button("Use") { confirmingCandy = true }
                        .disabled(!store.canUseTrainingCandy)
                        .help("Give the selected Pokémon one level, without EVs.")
                        .accessibilityLabel("Use Rare Candy")
                }
            }
            if confirmingCandy {
                HStack {
                    Text("Give this Pokémon one level?").font(.caption)
                    Spacer()
                    Button("Cancel") { confirmingCandy = false }.buttonStyle(.borderless)
                    Button("Give") {
                        confirmingCandy = false
                        _ = store.useTrainingCandy()
                    }
                    .disabled(!store.canUseTrainingCandy)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .controlSize(.small)
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Catching & training").font(.headline)
            Text("Catch grows your collection. Train gives the selected Pokémon XP and focused EVs. Balanced splits tokens equally between both.")
            Text("1 XP per 1,000 allocated tokens. 1 EV per 100,000 training tokens. EVs cap at 252 per stat and 510 total.")
            Text("Evolution follows the catching cycle, not training levels. Rare Candy adds one level without EVs. Existing Pokémon start at level 5.")
        }
        .font(.callout).fixedSize(horizontal: false, vertical: true)
    }

    private var modeExplanation: String {
        guard store.trainingPokemon != nil else { return "All tokens go to Catch until a trainee is available." }
        switch store.trainingMode {
        case .catching: return "All tokens grow your collection. Training is paused."
        case .training: return "All tokens train this Pokémon. Catching is paused."
        case .balanced: return "50% catching · 50% training this Pokémon."
        }
    }

    private var modeBinding: Binding<TrainingMode> {
        Binding(get: { store.trainingMode }, set: { store.setTrainingMode($0) })
    }

    private var targetBinding: Binding<String?> {
        Binding(get: {
            let id = store.trainingTargetID ?? store.trainingPokemon?.id
            guard let id, store.trainingCandidates.contains(where: { $0.id == id }) else { return nil }
            return id
        }, set: { store.setTrainingTarget($0) })
    }

    private var focusBinding: Binding<PokemonStat> {
        Binding(get: { store.trainingFocus }, set: { store.setTrainingFocus($0) })
    }

    private func candidateLabel(_ candidate: DexEntry) -> String {
        let name = candidate.names?[candidate.finalID].flatMap { store.language.resolveName($0) } ?? "#\(candidate.finalID)"
        return "\(name)\(candidate.isShiny ? " ✨" : "") · Lv. \(candidate.progression.level)"
    }
}
