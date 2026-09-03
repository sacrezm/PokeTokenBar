import Foundation
import Observation
struct TradingFriendRequest: Equatable, Sendable {
    let id: String
    let requesterID: String
    let addresseeID: String
    let status: String
    let other: TradingFriend
}
struct TradingInvite: Equatable, Sendable {
    let id: String
    let tradeID: String
    let inviterID: String
    let inviteeID: String
    let status: String
    let other: TradingFriend
}

enum TradingFeatureError: Error, Equatable, Sendable {
    case notRegistered
    case invalidResponse
    case server(status: Int, code: String)
    case missingPeer
    case invalidPeerKey
    case socketClosed
}

@MainActor
@Observable
final class TradingFeature {
    enum TradeStatus: String, Sendable {
        case opening, active, committed, acknowledged, failed
    }

    struct ActiveTrade: Equatable, Sendable {
        let tradeID: String
        let peer: TradingFriend
        var localPokemon: TradePokemon?
        var peerPokemon: TradePokemon?
        var localOffer: EncryptedTradeOffer?
        var peerOffer: EncryptedTradeOffer?
        var manifestDigest: String?
        var receipt: TradeReceipt?
        var status: TradeStatus
    }

    private(set) var trainerID: String?
    private(set) var trainerName: String?
    private(set) var friendCode: String?
    private(set) var friends: [TradingFriend] = []
    private(set) var friendRequests: [TradingFriendRequest] = []
    private(set) var invites: [TradingInvite] = []
    private(set) var heldInventory: [TradePokemon] = []
    private(set) var activeTrade: ActiveTrade?
    private(set) var lastError: String?

    private(set) var baseURL: URL
    @ObservationIgnored private let identityStore: any TradingIdentityStore
    @ObservationIgnored private let sidecar: TradingSidecar
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var pending: [String: PendingTrade]

    private static let profileKey = "PokeTokenBar.trading.profile.v1"
    private static let pendingKey = "PokeTokenBar.trading.pending.v1"
    private static let serverURLKey = "PokeTokenBar.trading.serverURL.v1"

    init(
        baseURL: URL,
        identityStore: any TradingIdentityStore,
        sidecar: TradingSidecar,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        if let stored = defaults.string(forKey: Self.serverURLKey),
           let url = URL(string: stored), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            self.baseURL = url
        } else {
            self.baseURL = baseURL
        }
        self.identityStore = identityStore
        self.sidecar = sidecar
        self.session = session
        self.defaults = defaults
        self.pending = Self.load([String: PendingTrade].self, key: Self.pendingKey, defaults: defaults) ?? [:]
        if let profile = Self.load(RemoteProfile.self, key: Self.profileKey, defaults: defaults) {
            apply(profile)
        }
    }

    var serverURL: String { baseURL.absoluteString }

    func setServerURL(_ value: String) throws {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { throw TradingFeatureError.invalidResponse }
        let localHosts = ["localhost", "127.0.0.1", "::1"]
        guard url.scheme?.lowercased() == "https" || localHosts.contains(url.host?.lowercased() ?? "")
        else { throw TradingFeatureError.invalidResponse }
        if baseURL != url {
            defaults.removeObject(forKey: Self.profileKey)
            trainerID = nil; trainerName = nil; friendCode = nil
            friends = []; friendRequests = []; invites = []; pending = [:]
            persistPending()
        }
        baseURL = url
        defaults.set(url.absoluteString, forKey: Self.serverURLKey)
    }

    func start() async {
        do {
            heldInventory = try await sidecar.heldInventory()
            try await refreshFriends()
            try await refreshInvites()
            try await recoverReceipts()
        } catch {
            lastError = message(for: error)
        }
    }

    func refreshInventory(from store: CompanionStore) async throws {
        guard let trainerID, let trainerName else { throw TradingFeatureError.notRegistered }
        let projected = CompanionCollectionAdapter(store: store).snapshot(
            trainerID: trainerID, trainerName: trainerName
        )
        heldInventory = try await sidecar.reconcile(local: projected)
    }

    func register(trainerName requestedName: String? = nil) async throws {
        guard trainerID == nil else { return }
        let name: String
        if let requestedName {
            try identityStore.setTrainerName(requestedName)
            name = requestedName
        } else if let stored = try identityStore.trainerName() {
            name = stored
        } else {
            throw TradingFeatureError.notRegistered
        }
        let identity = try identityStore.loadOrCreateIdentity()
        let body = RegisterBody(
            trainerName: name,
            agreementPublicKey: b64(identity.agreementPublicKey),
            token: try identityStore.bearerToken()
        )
        let data = try await request("/v1/trainers/register", method: "POST", body: body, authenticated: false)
        apply(try decode(RemoteProfile.self, from: data))
    }

    func rename(trainerName: String) async throws {
        guard trainerID != nil else { throw TradingFeatureError.notRegistered }
        let data = try await request("/v1/trainers/me", method: "PATCH", body: NameBody(trainerName: trainerName))
        let profile = try decode(RemoteProfile.self, from: data)
        try identityStore.setTrainerName(profile.trainerName)
        apply(profile)
    }

    @discardableResult
    func requestFriend(friendCode: String) async throws -> TradingFriendRequest {
        try requireRegistered()
        let data = try await request("/v1/friends/requests", method: "POST", body: CodeBody(friendCode: friendCode))
        let result = try decode(FriendRequestWire.self, from: data)
        let request = try friendRequest(result)
        try await refreshFriends()
        return request
    }

    @discardableResult
    func acceptFriend(requestID: String) async throws -> TradingFriendRequest {
        try requireRegistered()
        let data = try await request("/v1/friends/requests/\(path(requestID))/accept", method: "POST", body: EmptyBody())
        let result = try decode(FriendRequestWire.self, from: data)
        let accepted = try friendRequest(result)
        try await refreshFriends()
        return accepted
    }

    func refreshFriends() async throws {
        try requireRegistered()
        let data = try await request("/v1/friends", method: "GET")
        let result = try decode(FriendsWire.self, from: data)
        friends = try result.friends.map(friend)
        friendRequests = try result.requests.map(friendRequest)
        try await sidecar.setFriends(friends)
    }

    @discardableResult
    func invite(friendCode: String) async throws -> TradingInvite {
        try requireRegistered()
        let data = try await request("/v1/trades/invite", method: "POST", body: CodeBody(friendCode: friendCode))
        let result = try decode(InviteWire.self, from: data)
        let invite = try tradingInvite(result)
        pending[result.tradeID] = PendingTrade(outgoingCreatureID: "", peerID: invite.other.id)
        persistPending()
        try await refreshInvites()
        return invite
    }

    func refreshInvites() async throws {
        try requireRegistered()
        let data = try await request("/v1/trades/invites", method: "GET")
        let result = try decode(InvitesWire.self, from: data)
        invites = try result.invites.map(tradingInvite)
    }

    @discardableResult
    func acceptInvite(inviteID: String) async throws -> String {
        try requireRegistered()
        guard let invite = invites.first(where: { $0.id == inviteID }) else {
            throw TradingFeatureError.missingPeer
        }
        let data = try await request("/v1/trades/invites/\(path(inviteID))/accept", method: "POST", body: EmptyBody())
        let result = try decode(AcceptInviteWire.self, from: data)
        pending[result.tradeID] = PendingTrade(outgoingCreatureID: pending[result.tradeID]?.outgoingCreatureID ?? "", peerID: invite.other.id)
        persistPending()
        try await openTrade(tradeID: result.tradeID, peer: invite.other)
        return result.tradeID
    }

    func openTrade(tradeID: String, peer: TradingFriend) async throws {
        try requireRegistered()
        closeTrade()
        activeTrade = ActiveTrade(tradeID: tradeID, peer: peer, localPokemon: nil,
                                  peerPokemon: nil, localOffer: nil, peerOffer: nil,
                                  manifestDigest: nil, receipt: nil, status: .opening)
        var request = URLRequest(url: webSocketURL(tradeID: tradeID))
        request.setValue("Bearer \(try identityStore.bearerToken())", forHTTPHeaderField: "Authorization")
        request.setValue(trainerID, forHTTPHeaderField: "x-trade-actor")
        let task = session.webSocketTask(with: request)
        socket = task
        task.resume()
        activeTrade?.status = .active
        receiveTask = Task { [weak self, weak task] in
            guard let self, let task else { return }
            await self.receiveLoop(task)
        }
    }

    func closeTrade() {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        activeTrade = nil
    }

    func offer(_ pokemon: TradePokemon) async throws {
        guard let trade = activeTrade, trainerID != nil else { throw TradingFeatureError.notRegistered }
        guard try await sidecar.heldInventory().contains(where: { $0.creatureID == pokemon.creatureID }) else {
            throw TradingSidecarError.outgoingNotHeld(pokemon.creatureID)
        }
        let peerIdentity = TrainerIdentity(agreementPublicKey: trade.peer.agreementPublicKey)
        let encrypted = try TradeCrypto.encrypt(pokemon, tradeID: trade.tradeID,
                                                  recipient: peerIdentity, using: identityStore)
        pending[trade.tradeID] = PendingTrade(outgoingCreatureID: pokemon.creatureID, peerID: trade.peer.id)
        persistPending()
        try await send(type: "trade.offer", tradeID: trade.tradeID, body: [
            "recipientId": trade.peer.id,
            "nonce": b64(encrypted.nonce),
            "ciphertext": b64(encrypted.ciphertext),
            "tag": b64(encrypted.tag),
        ])
        activeTrade?.localPokemon = pokemon
        activeTrade?.localOffer = encrypted
    }

    func confirm() async throws {
        guard let trade = activeTrade, let digest = trade.manifestDigest else {
            throw TradingFeatureError.invalidResponse
        }
        try await send(type: "trade.confirm", tradeID: trade.tradeID, body: ["manifestDigest": digest])
    }

    func recoverReceipts() async throws {
        try requireRegistered()
        for (tradeID, record) in Array(pending) where !record.outgoingCreatureID.isEmpty {
            guard let peer = friends.first(where: { $0.id == record.peerID }) else { continue }
            let data: Data
            do { data = try await request("/v1/trades/\(path(tradeID))/receipt", method: "GET") } catch TradingFeatureError.server(status: 404, code: _) { continue }
            let receipt = try decode(ReceiptWire.self, from: data)
            guard let offerA = receipt.offerA, let offerB = receipt.offerB else {
                pending.removeValue(forKey: tradeID)
                continue
            }
            try await applyReceipt(receipt, offerA: offerA, offerB: offerB,
                                   outgoingCreatureID: record.outgoingCreatureID, peer: peer)
        }
        persistPending()
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                switch message {
                case .string(let value): await handleSocket(Data(value.utf8))
                case .data(let value): await handleSocket(value)
                @unknown default: throw TradingFeatureError.socketClosed
                }
            }
        } catch {
            if !Task.isCancelled { lastError = message(for: error); activeTrade?.status = .failed }
        }
    }

    private func handleSocket(_ data: Data) async {
        do {
            guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = envelope["v"] as? Int, version == 1,
                  let type = envelope["type"] as? String,
                  let tradeID = envelope["tradeId"] as? String,
                  let body = envelope["body"] as? [String: Any],
                  let trade = activeTrade, tradeID == trade.tradeID else { return }
            switch type {
            case "trade.ready", "trade.manifest":
                activeTrade?.manifestDigest = body["manifestDigest"] as? String
            case "trade.offer":
                try await receiveOffer(body, trade: trade)
            case "trade.committed":
                try await receiveCommitted(body, trade: trade)
            case "trade.acknowledged":
                activeTrade?.status = .acknowledged
            case "error":
                lastError = body["error"] as? String ?? "server error"
                activeTrade?.status = .failed
            default:
                break
            }
        } catch {
            lastError = message(for: error)
            activeTrade?.status = .failed
        }
    }

    private func receiveOffer(_ body: [String: Any], trade: ActiveTrade) async throws {
        guard let senderID = body["senderId"] as? String else { throw TradingFeatureError.invalidResponse }
        if senderID == trainerID { return }
        guard senderID == trade.peer.id else { throw TradingFeatureError.invalidResponse }
        guard let nonce = decodeB64(body["nonce"] as? String),
              let ciphertext = decodeB64(body["ciphertext"] as? String),
              let tag = decodeB64(body["tag"] as? String)
        else { throw TradingFeatureError.invalidResponse }
        let peerIdentity = TrainerIdentity(agreementPublicKey: trade.peer.agreementPublicKey)
        let localIdentity = try identityStore.loadOrCreateIdentity()
        let offer = EncryptedTradeOffer(tradeID: trade.tradeID, senderID: peerIdentity.trainerID,
                                        recipientID: localIdentity.trainerID, nonce: nonce,
                                        ciphertext: ciphertext, tag: tag)
        let pokemon = try TradeCrypto.decrypt(offer, from: peerIdentity, using: identityStore)
        activeTrade?.peerOffer = offer
        activeTrade?.peerPokemon = pokemon
    }

    private func receiveCommitted(_ body: [String: Any], trade: ActiveTrade) async throws {
        let data = try JSONSerialization.data(withJSONObject: body)
        let receipt = try decode(ReceiptWire.self, from: data)
        guard let offerA = receipt.offerA, let offerB = receipt.offerB,
              let pendingRecord = pending[trade.tradeID]
        else { throw TradingFeatureError.invalidResponse }
        try await applyReceipt(receipt, offerA: offerA, offerB: offerB,
                               outgoingCreatureID: pendingRecord.outgoingCreatureID,
                               peer: trade.peer)
        activeTrade?.status = .committed
    }

    private func applyReceipt(_ receipt: ReceiptWire, offerA: OfferWire, offerB: OfferWire,
                              outgoingCreatureID: String, peer: TradingFriend) async throws {
        guard let localID = trainerID, let a = receipt.trainerAID, let b = receipt.trainerBID,
              localID == a || localID == b,
              let digest = receipt.manifestDigest else { throw TradingFeatureError.invalidResponse }
        let remote = localID == a ? offerB : offerA
        let peerIdentity = TrainerIdentity(agreementPublicKey: peer.agreementPublicKey)
        let localIdentity = try identityStore.loadOrCreateIdentity()
        guard let nonce = decodeB64(remote.nonce), let ciphertext = decodeB64(remote.ciphertext),
              let tag = decodeB64(remote.tag) else { throw TradingFeatureError.invalidResponse }
        let encrypted = EncryptedTradeOffer(tradeID: receipt.tradeID, senderID: peerIdentity.trainerID,
                                            recipientID: localIdentity.trainerID, nonce: nonce,
                                            ciphertext: ciphertext, tag: tag)
        let pokemon = try TradeCrypto.decrypt(encrypted, from: peerIdentity, using: identityStore)
        let localReceipt = TradeReceipt(receiptID: receipt.tradeID, tradeID: receipt.tradeID,
                                        outgoingCreatureID: outgoingCreatureID, incoming: pokemon)
        _ = try await sidecar.apply(localReceipt)
        heldInventory = try await sidecar.heldInventory()
        activeTrade?.receipt = localReceipt
        activeTrade?.manifestDigest = digest
        _ = try await request("/v1/trades/\(path(receipt.tradeID))/ack", method: "POST",
                              body: ManifestBody(manifestDigest: digest))
        pending.removeValue(forKey: receipt.tradeID)
        persistPending()
    }

    private func send(type: String, tradeID: String, body: [String: Any]) async throws {
        guard let socket else { throw TradingFeatureError.socketClosed }
        var envelope: [String: Any] = ["v": 1, "messageId": UUID().uuidString,
                                       "type": type, "tradeId": tradeID, "body": body]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        envelope.removeAll(keepingCapacity: false)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func request(_ path: String, method: String, body: Encodable? = nil,
                         authenticated: Bool = true) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.timeoutInterval = 15
        if authenticated { request.setValue("Bearer \(try identityStore.bearerToken())", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TradingFeatureError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let code = (try? decode(ErrorWire.self, from: data).error) ?? "http_error"
            throw TradingFeatureError.server(status: response.statusCode, code: code)
        }
        return data
    }

    private func requireRegistered() throws {
        guard trainerID != nil else { throw TradingFeatureError.notRegistered }
    }

    private func apply(_ profile: RemoteProfile) {
        trainerID = profile.id
        trainerName = profile.trainerName
        friendCode = profile.friendCode
        defaults.set(try? JSONEncoder().encode(profile), forKey: Self.profileKey)
    }

    private func friend(_ value: ProfileWire) throws -> TradingFriend {
        guard let key = decodeB64(value.agreementPublicKey) else { throw TradingFeatureError.invalidPeerKey }
        return TradingFriend(id: value.id, trainerName: value.trainerName,
                             friendCode: value.friendCode, agreementPublicKey: key)
    }

    private func friendRequest(_ value: FriendRequestWire) throws -> TradingFriendRequest {
        TradingFriendRequest(id: value.id, requesterID: value.requesterID,
                             addresseeID: value.addresseeID, status: value.status,
                             other: try friend(value.other))
    }

    private func tradingInvite(_ value: InviteWire) throws -> TradingInvite {
        TradingInvite(id: value.id, tradeID: value.tradeID, inviterID: value.inviterID,
                      inviteeID: value.inviteeID, status: value.status, other: try friend(value.other))
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private func webSocketURL(tradeID: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = components.path + "/v1/trades/\(path(tradeID))/ws"
        return components.url!
    }

    private func persistPending() {
        defaults.set(try? JSONEncoder().encode(pending), forKey: Self.pendingKey)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func path(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func message(for error: Error) -> String {
        if case let TradingFeatureError.server(_, code) = error { return code }
        return String(describing: error)
    }

    private func b64(_ data: Data) -> String { TradingIdentityValidation.base64URL(data) }

    private func decodeB64(_ value: String?) -> Data? {
        guard let value, !value.isEmpty else { return nil }
        let normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard normalized.count % 4 != 1 else { return nil }
        return Data(base64Encoded: normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4))
    }

    private struct PendingTrade: Codable, Sendable { let outgoingCreatureID: String; let peerID: String }
    private struct RemoteProfile: Codable { let id: String; let trainerName: String; let friendCode: String; let agreementPublicKey: String }
    private struct RegisterBody: Codable { let trainerName: String; let agreementPublicKey: String; let token: String }
    private struct NameBody: Codable { let trainerName: String }
    private struct CodeBody: Codable { let friendCode: String }
    private struct ManifestBody: Codable { let manifestDigest: String }
    private struct EmptyBody: Codable {}
    private struct ErrorWire: Decodable { let error: String }
    private struct ProfileWire: Decodable { let id: String; let trainerName: String; let friendCode: String; let agreementPublicKey: String }
    private struct FriendRequestWire: Decodable { let id: String; let requesterID: String; let addresseeID: String; let status: String; let other: ProfileWire
        enum CodingKeys: String, CodingKey { case id, status, other; case requesterID = "requesterId"; case addresseeID = "addresseeId" }
    }
    private struct FriendsWire: Decodable { let friends: [ProfileWire]; let requests: [FriendRequestWire] }
    private struct InviteWire: Decodable { let id: String; let tradeID: String; let inviterID: String; let inviteeID: String; let status: String; let createdAt: Int?; let other: ProfileWire
        enum CodingKeys: String, CodingKey { case id, status, createdAt, other; case tradeID = "tradeId"; case inviterID = "inviterId"; case inviteeID = "inviteeId" }
    }
    private struct InvitesWire: Decodable { let invites: [InviteWire] }
    private struct AcceptInviteWire: Decodable { let tradeID: String; enum CodingKeys: String, CodingKey { case tradeID = "tradeId" } }
    private struct OfferWire: Decodable { let nonce: String; let ciphertext: String; let tag: String; let digest: String? }
    private struct ReceiptWire: Decodable {
        let tradeID: String
        let trainerAID: String?
        let trainerBID: String?
        let manifestDigest: String?
        let offerA: OfferWire?
        let offerB: OfferWire?
        let cleaned: Bool?
        enum CodingKeys: String, CodingKey {
            case manifestDigest, offerA, offerB, cleaned
            case tradeID = "tradeId"; case trainerAID = "trainerAId"; case trainerBID = "trainerBId"
        }
    }
}
