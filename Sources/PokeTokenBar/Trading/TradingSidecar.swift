import Foundation

/// Read-only projection over the existing catch-history save.  It reads only
/// `CompanionState.dex`; active synthetic entries and released entries never
/// cross into trading.  No method here can write to `CompanionStore`.
struct CompanionCollectionAdapter: Sendable {
    private let graduated: [DexEntry]

    init(state: CompanionState) {
        graduated = state.dex
    }

    @MainActor
    init(store: CompanionStore) {
        graduated = store.state.dex
    }

    func snapshot(trainerID: String, trainerName: String) -> [TradePokemon] {
        project(origin: OriginalTrainer(trainerID: trainerID, trainerName: trainerName))
    }

    func project(origin: OriginalTrainer) -> [TradePokemon] {
        var seen = Set<String>()
        return graduated.compactMap { entry in
            guard !entry.isReleased,
                  !entry.id.isEmpty,
                  !entry.chainOrder.isEmpty,
                  seen.insert(entry.id).inserted
            else { return nil }

            return TradePokemon(
                creatureID: entry.id,
                speciesID: entry.finalID,
                baseID: entry.baseID,
                chainOrder: entry.chainOrder,
                rarity: entry.rarity,
                isShiny: entry.isShiny,
                nature: entry.nature,
                caughtAt: entry.caughtAt,
                displayName: Self.displayName(entry),
                originalTrainer: origin,
                progression: entry.progression
            )
        }
    }

    private static func displayName(_ entry: DexEntry) -> String {
        guard let names = entry.names?[entry.finalID], !names.isEmpty else {
            return "#\(entry.finalID)"
        }
        for key in ["en", "en-US", "en-GB"] {
            if let name = names[key], !name.isEmpty { return name }
        }
        return names.sorted { $0.key < $1.key }.first?.value ?? "#\(entry.finalID)"
    }
}

/// Actor-owned local trading state.  Every mutating operation builds and
/// encodes a complete candidate before replacing the on-disk JSON, so a write
/// error cannot leak a partial in-memory transaction.
actor TradingSidecar {
    static let defaultFileName = "trading-state.json"

    private let fileURL: URL
    private var cached: TradingSidecarState?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AppStatePaths.directory().appendingPathComponent(Self.defaultFileName)
    }

    func state() throws -> TradingSidecarState {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let fresh = TradingSidecarState()
            cached = fresh
            return fresh
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode(TradingSidecarState.self, from: Data(contentsOf: fileURL))
            guard loaded.schemaVersion == TradingSidecarState.currentSchemaVersion else {
                throw TradingSidecarError.unsupportedSchema(loaded.schemaVersion)
            }
            cached = loaded
            return loaded
        } catch let error as TradingSidecarError {
            throw error
        } catch {
            throw TradingSidecarError.malformedState
        }
    }

    func reconcile(
        local projected: [TradePokemon],
        progressionOverrides: [String: PokemonProgression] = [:]
    ) throws -> [TradePokemon] {
        var next = try state()
        var changed = false
        for pokemon in projected {
            guard !pokemon.creatureID.isEmpty,
                  !next.transferredIDs.contains(pokemon.creatureID)
            else { continue }

            // A received individual is sidecar-owned even if an old local save
            // happens to contain the same ID. Never let that stale projection
            // rewrite its progression or any other received state.
            if next.receivedInventory.contains(where: { $0.creatureID == pokemon.creatureID }) {
                continue
            }

            if let heldIndex = next.heldInventory.firstIndex(where: {
                $0.creatureID == pokemon.creatureID
            }) {
                let existing = next.heldInventory[heldIndex]
                let progression = PokemonProgression.preservingProgress(
                    existing: existing.progression,
                    incoming: pokemon.progression
                )
                if progression != existing.progression {
                    next.heldInventory[heldIndex].progression = progression
                    changed = true
                }
                continue
            }

            next.heldInventory.append(pokemon)
            changed = true
        }

        // Overrides come from the single Core training transaction. They may
        // only update records that are currently held by this sidecar; an
        // entry for a released, transferred, or historical individual cannot
        // recreate ownership. Keep the received history in lockstep without
        // replacing its species or provenance snapshot.
        for heldIndex in next.heldInventory.indices {
            let creatureID = next.heldInventory[heldIndex].creatureID
            guard let incoming = progressionOverrides[creatureID] else { continue }

            var progression = PokemonProgression.preservingProgress(
                existing: next.heldInventory[heldIndex].progression,
                incoming: incoming
            )
            if let receivedIndex = next.receivedInventory.firstIndex(where: {
                $0.creatureID == creatureID
            }) {
                progression = PokemonProgression.preservingProgress(
                    existing: progression,
                    incoming: next.receivedInventory[receivedIndex].progression
                )
                if next.receivedInventory[receivedIndex].progression != progression {
                    next.receivedInventory[receivedIndex].progression = progression
                    changed = true
                }
            }
            if next.heldInventory[heldIndex].progression != progression {
                next.heldInventory[heldIndex].progression = progression
                changed = true
            }
        }
        if changed { try commit(next) }
        return next.heldInventory
    }

    func setFriends(_ friends: [TradingFriend]) throws {
        var next = try state()
        guard next.friendCache != friends else { return }
        next.friendCache = friends
        try commit(next)
    }

    func heldInventory() throws -> [TradePokemon] {
        try state().heldInventory
    }

    func receivedInventory() throws -> [TradePokemon] {
        try state().receivedInventory
    }

    func apply(_ receipt: TradeReceipt) throws -> ReceiptApplyResult {
        guard !receipt.receiptID.isEmpty,
              !receipt.tradeID.isEmpty,
              !receipt.outgoingCreatureID.isEmpty,
              !receipt.incoming.creatureID.isEmpty,
              receipt.incoming.creatureID != receipt.outgoingCreatureID
        else { throw TradingSidecarError.invalidReceipt }

        var next = try state()
        if next.appliedReceiptIDs.contains(receipt.receiptID) {
            return .alreadyApplied
        }

        guard let outgoingIndex = next.heldInventory.firstIndex(where: {
            $0.creatureID == receipt.outgoingCreatureID
        }) else {
            throw TradingSidecarError.outgoingNotHeld(receipt.outgoingCreatureID)
        }
        guard !next.heldInventory.contains(where: { $0.creatureID == receipt.incoming.creatureID }) else {
            throw TradingSidecarError.duplicateCreature(receipt.incoming.creatureID)
        }

        if let received = next.receivedInventory.first(where: { $0.creatureID == receipt.incoming.creatureID }),
           !TradeEvolution.isReturning(receipt.incoming, previously: received) {
            throw TradingSidecarError.duplicateCreature(receipt.incoming.creatureID)
        }

        // Evolve exactly once, in the same durable transaction as ownership.
        // If this individual was received before, retain the newer local
        // progression when an older return payload comes back.
        let evolvedIncoming = TradeEvolution.received(
            receipt.incoming,
            exchangedFor: next.heldInventory[outgoingIndex].speciesID
        )
        let incoming = Self.withProgression(
            evolvedIncoming,
            PokemonProgression.preservingProgress(
                existing: next.receivedInventory.first(where: {
                    $0.creatureID == evolvedIncoming.creatureID
                })?.progression ?? PokemonProgression(),
                incoming: evolvedIncoming.progression
            )
        )
        next.heldInventory.remove(at: outgoingIndex)
        next.heldInventory.append(incoming)
        if let index = next.receivedInventory.firstIndex(where: { $0.creatureID == incoming.creatureID }) {
            next.receivedInventory[index] = incoming
        } else {
            next.receivedInventory.append(incoming)
        }
        next.transferredIDs.insert(receipt.outgoingCreatureID)
        next.appliedReceiptIDs.insert(receipt.receiptID)
        try commit(next)
        return .applied
    }

    private static func withProgression(
        _ pokemon: TradePokemon,
        _ progression: PokemonProgression
    ) -> TradePokemon {
        guard progression != pokemon.progression else { return pokemon }
        return TradePokemon(
            creatureID: pokemon.creatureID,
            speciesID: pokemon.speciesID,
            baseID: pokemon.baseID,
            chainOrder: pokemon.chainOrder,
            rarity: pokemon.rarity,
            isShiny: pokemon.isShiny,
            nature: pokemon.nature,
            caughtAt: pokemon.caughtAt,
            displayName: pokemon.displayName,
            originalTrainer: pokemon.originalTrainer,
            progression: progression
        )
    }

    private func commit(_ next: TradingSidecarState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do { data = try encoder.encode(next) }
        catch { throw TradingSidecarError.malformedState }

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        do {
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw TradingSidecarError.malformedState
        }
        cached = next
    }
}

extension PokemonProgression {
    /// Keeps the more advanced snapshot and never downgrades durable
    /// progression when a stale local or trade payload is reconciled.
    static func preservingProgress(existing: Self, incoming: Self) -> Self {
        incoming.isAtLeast(existing) ? incoming : existing
    }

    private func isAtLeast(_ other: Self) -> Bool {
        guard totalExperience >= other.totalExperience else { return false }
        guard PokemonStat.allCases.allSatisfy({ ev(for: $0) >= other.ev(for: $0) }) else {
            return false
        }
        if totalExperience > other.totalExperience || totalEVs > other.totalEVs {
            return true
        }

        // Carries are loss-sensitive when the visible counter has not moved.
        // At a cap, a lower carry is ambiguous and must not reject an otherwise
        // equal snapshot.
        if totalExperience == other.totalExperience, !isMaxLevel,
           experienceRemainder < other.experienceRemainder {
            return false
        }
        if evs == other.evs, totalEVs < Self.maxTotalEVs,
           trainingRemainder < other.trainingRemainder {
            return false
        }
        return true
    }
}
