import CryptoKit
import Foundation

/// Public, non-secret profile data cached for a friend.  The agreement key is
/// needed locally to derive a per-trade encryption key; the bearer token and
/// the local agreement private key never belong in this model.
struct TradingFriend: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var trainerName: String
    var friendCode: String
    var agreementPublicKey: Data

    init(id: String, trainerName: String, friendCode: String, agreementPublicKey: Data) {
        self.id = id
        self.trainerName = trainerName
        self.friendCode = friendCode
        self.agreementPublicKey = agreementPublicKey
    }
}

/// The only origin data carried by a Pokémon.  All properties are immutable:
/// a receive or a later re-trade can carry this snapshot forward but cannot
/// rewrite it.  Authenticating locally-created records is deliberately out of
/// scope for this first slice.
struct OriginalTrainer: Codable, Equatable, Sendable {
    let trainerID: String
    let trainerName: String

    init(trainerID: String, trainerName: String) {
        self.trainerID = trainerID
        self.trainerName = trainerName
    }
}

/// Minimal encrypted payload content.  It deliberately contains no current
/// owner field: ownership is local sidecar state, while OG Trainer is payload
/// data and remains unchanged across trades.
struct TradePokemon: Codable, Equatable, Identifiable, Sendable {
    let creatureID: String
    let speciesID: Int
    let baseID: Int
    let chainOrder: [Int]
    let rarity: Rarity
    let isShiny: Bool
    let nature: PokemonNature?
    let caughtAt: Date?
    let displayName: String
    let originalTrainer: OriginalTrainer

    var id: String { creatureID }

    init(
        creatureID: String,
        speciesID: Int,
        baseID: Int,
        chainOrder: [Int],
        rarity: Rarity,
        isShiny: Bool,
        nature: PokemonNature?,
        caughtAt: Date?,
        displayName: String,
        originalTrainer: OriginalTrainer
    ) {
        self.creatureID = creatureID
        self.speciesID = speciesID
        self.baseID = baseID
        self.chainOrder = chainOrder
        self.rarity = rarity
        self.isShiny = isShiny
        self.nature = nature
        self.caughtAt = caughtAt
        self.displayName = displayName
        self.originalTrainer = originalTrainer
    }
}

/// The relay-visible part of one offer.  AES-GCM authenticates the metadata as
/// associated data; `digest` also gives the relay and receipt a cheap stable
/// identifier without exposing any Pokémon fields.
struct EncryptedTradeOffer: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let tradeID: String
    let senderID: String
    let recipientID: String
    let nonce: Data
    let ciphertext: Data
    let tag: Data
    let digest: Data

    init(
        version: Int = Self.currentVersion,
        tradeID: String,
        senderID: String,
        recipientID: String,
        nonce: Data,
        ciphertext: Data,
        tag: Data,
        digest: Data? = nil
    ) {
        self.version = version
        self.tradeID = tradeID
        self.senderID = senderID
        self.recipientID = recipientID
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
        self.digest = digest ?? Self.digest(
            version: version,
            tradeID: tradeID,
            senderID: senderID,
            recipientID: recipientID,
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )
    }

    var computedDigest: Data {
        Self.digest(version: version, tradeID: tradeID, senderID: senderID,
                    recipientID: recipientID, nonce: nonce,
                    ciphertext: ciphertext, tag: tag)
    }

    private static func digest(
        version: Int,
        tradeID: String,
        senderID: String,
        recipientID: String,
        nonce: Data,
        ciphertext: Data,
        tag: Data
    ) -> Data {
        var bytes = Data("ptb-offer-v1".utf8)
        bytes.append(UInt8(version & 0xff))
        append(Data(tradeID.utf8), to: &bytes)
        append(Data(senderID.utf8), to: &bytes)
        append(Data(recipientID.utf8), to: &bytes)
        append(nonce, to: &bytes)
        append(ciphertext, to: &bytes)
        append(tag, to: &bytes)
        return Data(SHA256.hash(data: bytes))
    }

    private static func append(_ value: Data, to bytes: inout Data) {
        var count = UInt32(value.count).bigEndian
        withUnsafeBytes(of: &count) { bytes.append(contentsOf: $0) }
        bytes.append(value)
    }
}

/// One committed trade.  The receipt carries the incoming cleartext only
/// after a client has decrypted its peer's encrypted offer.
struct TradeReceipt: Codable, Equatable, Sendable {
    let receiptID: String
    let tradeID: String
    let outgoingCreatureID: String
    let incoming: TradePokemon

    init(receiptID: String, tradeID: String, outgoingCreatureID: String, incoming: TradePokemon) {
        self.receiptID = receiptID
        self.tradeID = tradeID
        self.outgoingCreatureID = outgoingCreatureID
        self.incoming = incoming
    }
}

enum ReceiptApplyResult: Equatable, Sendable {
    case applied
    case alreadyApplied
}

/// Versioned, deliberately small local sidecar.  `heldInventory` is the
/// current local ownership view; `receivedInventory` keeps the latest received
/// form of each individual, including trade evolution. A Pokémon is in both while it
/// is held, and leaves only `heldInventory` when re-traded.
struct TradingSidecarState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var friendCache: [TradingFriend]
    var heldInventory: [TradePokemon]
    var receivedInventory: [TradePokemon]
    var transferredIDs: Set<String>
    var appliedReceiptIDs: Set<String>

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        friendCache: [TradingFriend] = [],
        heldInventory: [TradePokemon] = [],
        receivedInventory: [TradePokemon] = [],
        transferredIDs: Set<String> = [],
        appliedReceiptIDs: Set<String> = []
    ) {
        self.schemaVersion = schemaVersion
        self.friendCache = friendCache
        self.heldInventory = heldInventory
        self.receivedInventory = receivedInventory
        self.transferredIDs = transferredIDs
        self.appliedReceiptIDs = appliedReceiptIDs
    }
}

enum TradingSidecarError: Error, Equatable, Sendable {
    case malformedState
    case unsupportedSchema(Int)
    case invalidReceipt
    case outgoingNotHeld(String)
    case duplicateCreature(String)
}
