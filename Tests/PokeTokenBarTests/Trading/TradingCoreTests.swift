import XCTest
import SwiftUI
@testable import PokeTokenBar

final class TradingCoreTests: XCTestCase {
    func testOfferUsesECDHHKDFAESGCMAndPreservesOGTrainer() throws {
        let alice = try InMemoryTradingIdentityStore()
        let bob = try InMemoryTradingIdentityStore()
        let bobIdentity = try bob.loadOrCreateIdentity()
        let original = OriginalTrainer(trainerID: "alice", trainerName: "Ash")
        let pokemon = TradePokemon(
            creatureID: "creature-1", speciesID: 25, baseID: 25,
            chainOrder: [25], rarity: .common, isShiny: true,
            nature: .jolly, caughtAt: Date(timeIntervalSince1970: 1),
            displayName: "Pikachu", originalTrainer: original
        )

        let offer = try TradeCrypto.encrypt(
            pokemon, tradeID: "trade-1", recipient: bobIdentity,
            using: alice, nonce: Data(repeating: 7, count: 12)
        )
        XCTAssertNotEqual(offer.ciphertext, try JSONEncoder().encode(pokemon))
        let opened = try TradeCrypto.decrypt(
            offer, from: try alice.loadOrCreateIdentity(), using: bob
        )
        XCTAssertEqual(opened, pokemon)
        XCTAssertEqual(opened.originalTrainer, original)
    }

    func testTamperedOfferCannotBeOpened() throws {
        let alice = try InMemoryTradingIdentityStore()
        let bob = try InMemoryTradingIdentityStore()
        let identity = try bob.loadOrCreateIdentity()
        let pokemon = TradePokemon(
            creatureID: "c", speciesID: 1, baseID: 1, chainOrder: [1],
            rarity: .common, isShiny: false, nature: nil, caughtAt: nil,
            displayName: "Bulbasaur", originalTrainer: OriginalTrainer(trainerID: "a", trainerName: "Ash")
        )
        let offer = try TradeCrypto.encrypt(pokemon, tradeID: "t", recipient: identity, using: alice)
        let tampered = EncryptedTradeOffer(
            tradeID: offer.tradeID, senderID: offer.senderID, recipientID: offer.recipientID,
            nonce: offer.nonce, ciphertext: offer.ciphertext + Data([0]), tag: offer.tag,
            digest: offer.digest
        )
        XCTAssertThrowsError(try TradeCrypto.decrypt(
            tampered, from: try alice.loadOrCreateIdentity(), using: bob
        ))
    }

    func testAdapterProjectsOnlyPersistedGraduatesAndNeverMutatesState() {
        let kept = DexEntry(id: "kept", baseID: 1, finalID: 2, chainOrder: [1, 2],
                            rarity: .common, caughtAt: Date(), names: [2: ["en": "Ivysaur"]])
        let released = DexEntry(id: "released", baseID: 3, finalID: 3, chainOrder: [3],
                                rarity: .rare, caughtAt: Date(), releasedAt: Date())
        var state = CompanionState()
        state.dex = [kept, released]
        let before = state
        let projected = CompanionCollectionAdapter(state: state).snapshot(
            trainerID: "trainer-a", trainerName: "Ash"
        )
        XCTAssertEqual(projected.map(\.creatureID), ["kept"])
        XCTAssertEqual(projected.first?.displayName, "Ivysaur")
        XCTAssertEqual(projected.first?.originalTrainer,
                       OriginalTrainer(trainerID: "trainer-a", trainerName: "Ash"))
        XCTAssertEqual(state.dex.map(\.id), before.dex.map(\.id))
        XCTAssertEqual(state.dex.map(\.releasedAt), before.dex.map(\.releasedAt))
    }

    func testFeatureUsesRESTContractAndPersistsServerURL() async throws {
        let alice = try InMemoryTradingIdentityStore(
            trainerName: "Ash", bearerToken: String(repeating: "a", count: 32)
        )
        let bob = try InMemoryTradingIdentityStore(trainerName: "Misty")
        let aliceIdentity = try alice.loadOrCreateIdentity()
        let bobIdentity = try bob.loadOrCreateIdentity()
        let bobKey = TradingIdentityValidation.base64URL(bobIdentity.agreementPublicKey)
        let aliceKey = TradingIdentityValidation.base64URL(aliceIdentity.agreementPublicKey)
        let bobProfile: [String: Any] = [
            "id": bobIdentity.trainerID, "trainerName": "Misty", "friendCode": "MISTY123",
            "agreementPublicKey": bobKey,
        ]
        let aliceProfile: [String: Any] = [
            "id": aliceIdentity.trainerID, "trainerName": "Ash", "friendCode": "ASH12345",
            "agreementPublicKey": aliceKey,
        ]
        let friendState: [String: Any] = [
            "id": "friend-1", "requesterId": aliceIdentity.trainerID,
            "addresseeId": bobIdentity.trainerID, "status": "accepted",
            "createdAt": 1, "updatedAt": 1, "other": bobProfile,
        ]
        let invite: [String: Any] = [
            "id": "invite-1", "tradeId": "trade-1", "inviterId": aliceIdentity.trainerID,
            "inviteeId": bobIdentity.trainerID, "status": "pending", "createdAt": 1,
            "other": bobProfile,
        ]
        let recorder = TradingFeatureURLProtocol.Recorder()
        TradingFeatureURLProtocol.handler = { request in
            recorder.record(request)
            let path = request.url?.path ?? ""
            switch (request.httpMethod, path) {
            case ("POST", "/v1/trainers/register"):
                return TradingFeatureTestResponse.json(aliceProfile, status: 201)
            case ("PATCH", "/v1/trainers/me"):
                return TradingFeatureTestResponse.json(aliceProfile.merging(["trainerName": "Gary"]) { _, new in new })
            case ("GET", "/v1/friends"), ("GET", "/v1/friends/requests"):
                return TradingFeatureTestResponse.json(["friends": [bobProfile], "requests": [friendState]])
            case ("POST", "/v1/friends/requests"):
                return TradingFeatureTestResponse.json(friendState, status: 201)
            case ("POST", "/v1/friends/requests/friend-1/accept"):
                return TradingFeatureTestResponse.json(friendState)
            case ("POST", "/v1/trades/invite"):
                return TradingFeatureTestResponse.json(invite, status: 201)
            case ("GET", "/v1/trades/invites"):
                return TradingFeatureTestResponse.json(["invites": [invite]])
            default:
                return TradingFeatureTestResponse.json(["error": "unexpected"], status: 500)
            }
        }
        defer { TradingFeatureURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TradingFeatureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let sidecarURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-feature-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: sidecarURL) }
        let feature = await MainActor.run {
            let defaults = UserDefaults(suiteName: "ptb-feature-\(UUID().uuidString)")!
            return TradingFeature(baseURL: URL(string: "https://example.test")!,
                                  identityStore: alice,
                                  sidecar: TradingSidecar(fileURL: sidecarURL),
                                  session: session, defaults: defaults)
        }

        try await feature.register()
        try await feature.rename(trainerName: "Gary")
        try await feature.refreshFriends()
        _ = try await feature.requestFriend(friendCode: "MISTY123")
        _ = try await feature.acceptFriend(requestID: "friend-1")
        _ = try await feature.invite(friendCode: "MISTY123")
        try await feature.refreshInvites()
        let values = await MainActor.run {
            (feature.trainerID, feature.trainerName, feature.friends.first?.id,
             feature.invites.first?.tradeID, feature.serverURL)
        }
        do {
            try await feature.setServerURL("http://public.example")
            XCTFail("public trade relays must use HTTPS")
        } catch {}
        try await feature.setServerURL("https://override.example")
        XCTAssertEqual(values.0, aliceIdentity.trainerID)
        XCTAssertEqual(values.1, "Gary")
        XCTAssertEqual(values.2, bobIdentity.trainerID)
        XCTAssertEqual(values.3, "trade-1")
        XCTAssertEqual(values.4, "https://example.test")
        let endpoint = await feature.serverURL
        XCTAssertEqual(endpoint, "https://override.example")
        let requests = recorder.snapshot()
        XCTAssertTrue(requests.contains { $0.url?.path == "/v1/trainers/register" && $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertTrue(requests.dropFirst().contains { $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(String(repeating: "a", count: 32))" })
    }
}

final class TradingSidecarTests: XCTestCase {
    func testReceiptApplyIsAtomicAndIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-trading-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sidecar = TradingSidecar(fileURL: directory.appendingPathComponent("trading.json"))
        let outgoing = pokemon(id: "outgoing", trainerID: "alice", trainerName: "Ash")
        let incoming = pokemon(id: "incoming", trainerID: "original", trainerName: "Misty")
        _ = try await sidecar.reconcile(local: [outgoing])

        let receipt = TradeReceipt(receiptID: "receipt-1", tradeID: "trade-1",
                                   outgoingCreatureID: outgoing.creatureID, incoming: incoming)
        let firstApply = try await sidecar.apply(receipt)
        let duplicateApply = try await sidecar.apply(receipt)
        XCTAssertEqual(firstApply, .applied)
        XCTAssertEqual(duplicateApply, .alreadyApplied)

        var state = try await sidecar.state()
        XCTAssertEqual(state.heldInventory, [incoming])
        XCTAssertEqual(state.receivedInventory, [incoming])
        XCTAssertEqual(state.transferredIDs, [outgoing.creatureID])
        XCTAssertEqual(state.appliedReceiptIDs, [receipt.receiptID])

        let invalid = TradeReceipt(receiptID: "receipt-2", tradeID: "trade-2",
                                   outgoingCreatureID: "missing",
                                   incoming: pokemon(id: "new", trainerID: "x", trainerName: "Xx"))
        do {
            _ = try await sidecar.apply(invalid)
            XCTFail("an outgoing creature that is not held must not apply")
        } catch {
            XCTAssertEqual(error as? TradingSidecarError, .outgoingNotHeld("missing"))
        }
        state = try await sidecar.state()
        XCTAssertEqual(state.heldInventory, [incoming])
        XCTAssertEqual(state.appliedReceiptIDs, [receipt.receiptID])

        let restarted = TradingSidecar(fileURL: directory.appendingPathComponent("trading.json"))
        let restartedApply = try await restarted.apply(receipt)
        let restartedState = try await restarted.state()
        XCTAssertEqual(restartedApply, .alreadyApplied)
        XCTAssertEqual(restartedState, state)
    }

    func testReconcilePreservesExistingOGOnTrainerRename() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let sidecar = TradingSidecar(fileURL: url)
        let first = pokemon(id: "same", trainerID: "alice", trainerName: "Ash")
        let renamed = pokemon(id: "same", trainerID: "alice", trainerName: "Gary")
        _ = try await sidecar.reconcile(local: [first])
        _ = try await sidecar.reconcile(local: [renamed])
        let held = try await sidecar.heldInventory()
        XCTAssertEqual(held.first?.originalTrainer, first.originalTrainer)
    }

    private func pokemon(id: String, trainerID: String, trainerName: String) -> TradePokemon {
        TradePokemon(creatureID: id, speciesID: 1, baseID: 1, chainOrder: [1],
                     rarity: .common, isShiny: false, nature: nil, caughtAt: nil,
                     displayName: "Bulbasaur",
                     originalTrainer: OriginalTrainer(trainerID: trainerID, trainerName: trainerName))
    }
}

final class TradingPresentationTests: XCTestCase {
    @MainActor
    func testCompletionCardFitsThePopover() {
        let receipt = TradeReceipt(receiptID: "layout", tradeID: "layout", outgoingCreatureID: "out",
                                   incoming: pokemon(id: "in", species: 531, name: "Audino"))
        let controller = NSHostingController(rootView: TradeCompletionView(receipt: receipt, onDismiss: {})
            .frame(width: PopoverMetrics.contentWidth))
        let size = controller.sizeThatFits(in: CGSize(width: PopoverMetrics.contentWidth, height: 150))
        XCTAssertLessThanOrEqual(size.width, PopoverMetrics.contentWidth)
        XCTAssertLessThanOrEqual(size.height, 100)
    }

    @MainActor
    func testReceivedSpeciesAppearsWithoutInventingEarlierEvolutionsOrDuplicatingSpecies() {
        let caught = CompanionStore.DexSpecies(id: 25, name: "Pikachu", rarity: .common,
                                               isShiny: false, isRaising: true)
        let received = pokemon(id: "audino", species: 531, name: "Audino")
        let shiny = pokemon(id: "pikachu", species: 25, name: "Pikachu", shiny: true)
        let result = TradingCollectionProjection.species(original: [caught], received: [received, shiny, received])
        XCTAssertEqual(result.map(\.id), [25, 531])
        XCTAssertTrue(result[0].isShiny)
        XCTAssertTrue(result[0].isRaising)
        XCTAssertEqual(result[1].name, "Audino")
        XCTAssertFalse(caught.isShiny, "Projection must not rewrite hatch records")
    }

    @MainActor
    func testCompletionUpdatesCollectionAndNotifiesOnceAfterDurableWrite() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sidecar = TradingSidecar(fileURL: dir.appendingPathComponent("trades.json"))
        let outgoing = pokemon(id: "out", species: 25, name: "Pikachu")
        let incoming = pokemon(id: "in", species: 531, name: "Audino")
        _ = try await sidecar.reconcile(local: [outgoing])
        let suite = "trading-presentation-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let feature = TradingFeature(baseURL: URL(string: "https://example.test")!,
                                     identityStore: try InMemoryTradingIdentityStore(),
                                     sidecar: sidecar, defaults: defaults)
        var activities: [TradingActivity] = []
        feature.onActivity = { activities.append($0) }
        let receipt = TradeReceipt(receiptID: "r", tradeID: "t", outgoingCreatureID: "out", incoming: incoming)
        try await feature.applyLocalReceipt(receipt)
        XCTAssertEqual(feature.heldInventory, [incoming])
        XCTAssertEqual(feature.receivedInventory, [incoming])
        XCTAssertEqual(feature.completion, receipt)
        XCTAssertEqual(activities.count, 1)
        XCTAssertTrue(feature.hasUnreadActivity)
        feature.dismissCompletion()
        feature.markActivityRead()
        try await feature.applyLocalReceipt(receipt)
        XCTAssertNil(feature.completion)
        XCTAssertFalse(feature.hasUnreadActivity)
        XCTAssertEqual(activities.count, 1)
        let restarted = TradingFeature(baseURL: URL(string: "https://example.test")!,
                                       identityStore: try InMemoryTradingIdentityStore(),
                                       sidecar: TradingSidecar(fileURL: dir.appendingPathComponent("trades.json")),
                                       defaults: defaults)
        await restarted.start()
        XCTAssertEqual(restarted.receivedInventory, [incoming])
        XCTAssertNil(restarted.completion, "Old receipts do not replay the success animation at launch")
        let bad = TradeReceipt(receiptID: "bad", tradeID: "bad", outgoingCreatureID: "missing",
                               incoming: pokemon(id: "new", species: 1, name: "Bulbasaur"))
        do { try await feature.applyLocalReceipt(bad); XCTFail("invalid receipt must fail") } catch {}
        XCTAssertEqual(activities.count, 1)
    }

    @MainActor
    func testBackgroundPollDetectsIncomingRequestsWithoutPopoverAndDeduplicatesAcrossRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "trading-alerts-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = try InMemoryTradingIdentityStore()
        let publicKey = TradingIdentityValidation.base64URL(try identity.loadOrCreateIdentity().agreementPublicKey)
        let profile = ["id": "me", "trainerName": "Ash", "friendCode": "ASH12345", "agreementPublicKey": publicKey]
        defaults.set(try JSONSerialization.data(withJSONObject: profile), forKey: "PokeTokenBar.trading.profile.v1")
        let peer = ["id": "peer", "trainerName": "Misty", "friendCode": "MISTY123", "agreementPublicKey": publicKey]
        TradingFeatureURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/friends":
                return TradingFeatureTestResponse.json(["friends": [peer], "requests": [
                    ["id": "incoming-friend", "requesterId": "peer", "addresseeId": "me", "status": "pending", "other": peer],
                    ["id": "outgoing-friend", "requesterId": "me", "addresseeId": "peer", "status": "pending", "other": peer]]])
            case "/v1/trades/invites":
                return TradingFeatureTestResponse.json(["invites": [
                    ["id": "incoming-trade", "tradeId": "t1", "inviterId": "peer", "inviteeId": "me", "status": "pending", "other": peer],
                    ["id": "outgoing-trade", "tradeId": "t2", "inviterId": "me", "inviteeId": "peer", "status": "pending", "other": peer]]])
            default: return TradingFeatureTestResponse.json(["error": "unexpected"], status: 500)
            }
        }
        defer { TradingFeatureURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TradingFeatureURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        func makeFeature() -> TradingFeature {
            TradingFeature(baseURL: URL(string: "https://example.test")!, identityStore: identity,
                           sidecar: TradingSidecar(fileURL: dir.appendingPathComponent("trades.json")),
                           session: session, defaults: defaults)
        }
        let feature = makeFeature()
        var events: [TradingActivity] = []
        let incoming = expectation(description: "Background poll emits both incoming alerts without a view")
        incoming.expectedFulfillmentCount = 2
        feature.onActivity = { events.append($0); incoming.fulfill() }
        feature.startBackgroundUpdates(intervalNanoseconds: 10_000_000)
        feature.startBackgroundUpdates(intervalNanoseconds: 10_000_000) // Starting twice is harmless.
        await fulfillment(of: [incoming], timeout: 2)
        feature.stopBackgroundUpdates()
        XCTAssertEqual(Set(events.map(\.id)), ["friend:incoming-friend", "invite:incoming-trade"])
        feature.markActivityRead()
        _ = await feature.pollUpdates()
        XCTAssertEqual(events.count, 2)
        XCTAssertFalse(feature.hasUnreadActivity)
        let restarted = makeFeature()
        restarted.onActivity = { events.append($0) }
        await restarted.start()
        XCTAssertEqual(events.count, 2)
        XCTAssertFalse(restarted.hasUnreadActivity)
    }

    private func pokemon(id: String, species: Int, name: String, shiny: Bool = false) -> TradePokemon {
        TradePokemon(creatureID: id, speciesID: species, baseID: species, chainOrder: [species],
                     rarity: .common, isShiny: shiny, nature: nil, caughtAt: nil, displayName: name,
                     originalTrainer: OriginalTrainer(trainerID: "original", trainerName: "Misty"))
    }
}

private final class TradingFeatureURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [URLRequest] = []
        func record(_ request: URLRequest) { lock.lock(); requests.append(request); lock.unlock() }
        func snapshot() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let result = Self.handler?(request), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: result.0,
                                             httpVersion: nil, headerFields: ["Content-Type": "application/json"])
        else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private enum TradingFeatureTestResponse {
    static func json(_ object: Any, status: Int = 200) -> (Int, Data) {
        (status, try! JSONSerialization.data(withJSONObject: object))
    }
}
