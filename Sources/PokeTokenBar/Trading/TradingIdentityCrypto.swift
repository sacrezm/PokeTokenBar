import CryptoKit
import Foundation

struct TrainerIdentity: Codable, Equatable, Sendable {
    let trainerID: String
    let agreementPublicKey: Data

    init(agreementPublicKey: Data) {
        self.agreementPublicKey = agreementPublicKey
        self.trainerID = Self.id(for: agreementPublicKey)
    }

    static func id(for publicKey: Data) -> String {
        let digest = Data(SHA256.hash(data: publicKey))
        let encoded = digest.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "ptb-trainer-\(encoded)"
    }
}

enum TradingIdentityError: Error, Equatable, Sendable {
    case invalidName
    case invalidStoredKey
    case invalidPeerKey
    case missingKeychainValue
    case keychainRead(Int32)
    case keychainWrite(Int32)
}

/// One small seam for the real Keychain adapter and deterministic crypto tests.
protocol TradingIdentityStore: Sendable {
    func loadOrCreateIdentity() throws -> TrainerIdentity
    func trainerName() throws -> String?
    func setTrainerName(_ name: String) throws
    func bearerToken() throws -> String
    func deriveSharedKey(peerAgreementPublicKey: Data, tradeID: String) throws -> SymmetricKey
}

enum TradingIdentityValidation {
    static func name(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...20).contains(normalized.count),
              !normalized.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f })
        else { throw TradingIdentityError.invalidName }
        return normalized
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The private agreement key, bearer token and trainer name are all generic
/// Keychain values.  Only the public key and a derived session key cross this
/// adapter's interface.
#if os(macOS)
import Security

final class KeychainIdentityStore: TradingIdentityStore, @unchecked Sendable {
    static let defaultService = "com.chattymin.PokeTokenBar.trading.v1"

    private let service: String
    private let account: String

    init(service: String = KeychainIdentityStore.defaultService, account: String = "device") {
        self.service = service
        self.account = account
    }

    func loadOrCreateIdentity() throws -> TrainerIdentity {
        let key = try agreementKey()
        return TrainerIdentity(agreementPublicKey: key.publicKey.x963Representation)
    }

    func trainerName() throws -> String? {
        guard let data = try read(account: "trainer-name") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setTrainerName(_ name: String) throws {
        let valid = try TradingIdentityValidation.name(name)
        try write(Data(valid.utf8), account: "trainer-name")
    }

    func bearerToken() throws -> String {
        if let existing = try read(account: "bearer-token"),
           let token = String(data: existing, encoding: .utf8), !token.isEmpty {
            return token
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw TradingIdentityError.keychainWrite(errSecAllocate)
        }
        let token = TradingIdentityValidation.base64URL(Data(bytes))
        if try add(Data(token.utf8), account: "bearer-token") == false {
            return (try read(account: "bearer-token")).flatMap { String(data: $0, encoding: .utf8) } ?? token
        }
        return (try read(account: "bearer-token")).flatMap { String(data: $0, encoding: .utf8) } ?? token
    }

    func deriveSharedKey(peerAgreementPublicKey: Data, tradeID: String) throws -> SymmetricKey {
        let peer: P256.KeyAgreement.PublicKey
        do { peer = try P256.KeyAgreement.PublicKey(x963Representation: peerAgreementPublicKey) }
        catch { throw TradingIdentityError.invalidPeerKey }
        do {
            let shared = try agreementKey().sharedSecretFromKeyAgreement(with: peer)
            return shared.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data("ptb-trade-v1".utf8),
                sharedInfo: Data("ptb-trade-v1/\(tradeID)".utf8),
                outputByteCount: 32
            )
        } catch let error as TradingIdentityError { throw error }
        catch { throw TradingIdentityError.invalidPeerKey }
    }

    private func agreementKey() throws -> P256.KeyAgreement.PrivateKey {
        if let data = try read(account: "agreement-private-key") {
            do { return try P256.KeyAgreement.PrivateKey(rawRepresentation: data) }
            catch { throw TradingIdentityError.invalidStoredKey }
        }
        let created = P256.KeyAgreement.PrivateKey()
        if try add(created.rawRepresentation, account: "agreement-private-key") == false {
            guard let stored = try read(account: "agreement-private-key") else {
                throw TradingIdentityError.missingKeychainValue
            }
            do { return try P256.KeyAgreement.PrivateKey(rawRepresentation: stored) }
            catch { throw TradingIdentityError.invalidStoredKey }
        }
        if let stored = try read(account: "agreement-private-key") {
            do { return try P256.KeyAgreement.PrivateKey(rawRepresentation: stored) }
            catch { throw TradingIdentityError.invalidStoredKey }
        }
        return created
    }

    private func query(account: String, returningData: Bool = true) -> [String: Any] {
        var result: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(self.account).\(account)",
        ]
        if returningData {
            result[kSecMatchLimit as String] = kSecMatchLimitOne
            result[kSecReturnData as String] = true
        }
        return result
    }

    private func read(account: String) throws -> Data? {
        var result: CFTypeRef?
        var request = query(account: account)
        KeychainNoUIQuery.apply(to: &request)
        let status = KeychainReader.copyMatching(request, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw TradingIdentityError.keychainRead(status)
        }
    }

    private func add(_ data: Data, account: String) throws -> Bool {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(self.account).\(account)",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecDuplicateItem { return false }
        throw TradingIdentityError.keychainWrite(status)
    }

    private func write(_ data: Data, account: String) throws {
        if try add(data, account: account) { return }
        let selector = query(account: account, returningData: false) as CFDictionary
        let update = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(selector, update)
        guard updateStatus == errSecSuccess else { throw TradingIdentityError.keychainWrite(updateStatus) }
    }
}
#endif

/// In-memory adapter is intentionally the second adapter at the identity seam;
/// it keeps tests off the user's real Keychain while exercising identical ECDH.
final class InMemoryTradingIdentityStore: TradingIdentityStore, @unchecked Sendable {
    private let agreement: P256.KeyAgreement.PrivateKey
    private let token: String
    private var name: String?

    init(
        agreementKey: P256.KeyAgreement.PrivateKey = P256.KeyAgreement.PrivateKey(),
        trainerName: String? = nil,
        bearerToken: String = "test-bearer"
    ) throws {
        self.agreement = agreementKey
        self.token = bearerToken
        if let trainerName { self.name = try TradingIdentityValidation.name(trainerName) }
    }

    func loadOrCreateIdentity() throws -> TrainerIdentity {
        TrainerIdentity(agreementPublicKey: agreement.publicKey.x963Representation)
    }

    func trainerName() throws -> String? { name }

    func setTrainerName(_ name: String) throws {
        self.name = try TradingIdentityValidation.name(name)
    }

    func bearerToken() throws -> String { token }

    func deriveSharedKey(peerAgreementPublicKey: Data, tradeID: String) throws -> SymmetricKey {
        let peer: P256.KeyAgreement.PublicKey
        do { peer = try P256.KeyAgreement.PublicKey(x963Representation: peerAgreementPublicKey) }
        catch { throw TradingIdentityError.invalidPeerKey }
        do {
            let shared = try agreement.sharedSecretFromKeyAgreement(with: peer)
            return shared.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data("ptb-trade-v1".utf8),
                sharedInfo: Data("ptb-trade-v1/\(tradeID)".utf8),
                outputByteCount: 32
            )
        } catch { throw TradingIdentityError.invalidPeerKey }
    }
}

enum TradeCryptoError: Error, Equatable, Sendable {
    case invalidOffer
    case wrongRecipient
    case wrongSender
    case digestMismatch
    case decryptionFailed
    case encodingFailed
}

enum TradeCrypto {
    static func encrypt(
        _ pokemon: TradePokemon,
        tradeID: String,
        recipient: TrainerIdentity,
        using identityStore: any TradingIdentityStore,
        nonce: Data? = nil
    ) throws -> EncryptedTradeOffer {
        let sender = try identityStore.loadOrCreateIdentity()
        guard !tradeID.isEmpty else { throw TradeCryptoError.invalidOffer }
        let nonce = nonce ?? Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        guard nonce.count == 12 else { throw TradeCryptoError.invalidOffer }
        let key: SymmetricKey
        do {
            key = try identityStore.deriveSharedKey(
                peerAgreementPublicKey: recipient.agreementPublicKey,
                tradeID: tradeID
            )
        } catch { throw TradeCryptoError.decryptionFailed }
        let aad = associatedData(version: EncryptedTradeOffer.currentVersion,
                                  tradeID: tradeID, senderID: sender.trainerID,
                                  recipientID: recipient.trainerID)
        let plaintext: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            plaintext = try encoder.encode(pokemon)
        } catch { throw TradeCryptoError.encodingFailed }
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key,
                                          nonce: AES.GCM.Nonce(data: nonce),
                                          authenticating: aad)
            return EncryptedTradeOffer(
                tradeID: tradeID, senderID: sender.trainerID,
                recipientID: recipient.trainerID, nonce: nonce,
                ciphertext: sealed.ciphertext, tag: sealed.tag
            )
        } catch { throw TradeCryptoError.decryptionFailed }
    }

    static func decrypt(
        _ offer: EncryptedTradeOffer,
        from sender: TrainerIdentity,
        using identityStore: any TradingIdentityStore
    ) throws -> TradePokemon {
        let recipient = try identityStore.loadOrCreateIdentity()
        guard offer.version == EncryptedTradeOffer.currentVersion,
              offer.recipientID == recipient.trainerID else { throw TradeCryptoError.wrongRecipient }
        guard offer.senderID == sender.trainerID else { throw TradeCryptoError.wrongSender }
        guard offer.nonce.count == 12, offer.tag.count == 16, !offer.ciphertext.isEmpty,
              offer.digest == offer.computedDigest else { throw TradeCryptoError.digestMismatch }
        let key: SymmetricKey
        do {
            key = try identityStore.deriveSharedKey(
                peerAgreementPublicKey: sender.agreementPublicKey,
                tradeID: offer.tradeID
            )
        } catch { throw TradeCryptoError.decryptionFailed }
        let aad = associatedData(version: offer.version, tradeID: offer.tradeID,
                                  senderID: offer.senderID, recipientID: offer.recipientID)
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: offer.nonce),
                ciphertext: offer.ciphertext,
                tag: offer.tag
            )
            let plaintext = try AES.GCM.open(box, using: key, authenticating: aad)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(TradePokemon.self, from: plaintext)
        } catch { throw TradeCryptoError.decryptionFailed }
    }

    private static func associatedData(version: Int, tradeID: String,
                                       senderID: String, recipientID: String) -> Data {
        Data("ptb-offer-aad-v1\n\(version)\n\(tradeID)\n\(senderID)\n\(recipientID)\n".utf8)
    }
}
