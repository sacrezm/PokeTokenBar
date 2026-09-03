import AppKit
import SwiftUI

@MainActor
struct TradingView: View {
    @Environment(TradingFeature.self) private var trading
    @Environment(CompanionStore.self) private var companion
    @State private var serverURL = ""
    @State private var trainerName = ""
    @State private var friendCode = ""
    @State private var selectedPokemonID = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if trading.trainerID == nil { setup } else { account }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 390)
        .task {
            if serverURL.isEmpty { serverURL = trading.serverURL }
            await reload()
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remote trading").font(.headline)
            Text("Choose the small relay you want to use. Pokémon details are encrypted before leaving this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("https://…workers.dev", text: $serverURL)
                .textFieldStyle(.roundedBorder)
            TextField("Trainer name", text: $trainerName)
                .textFieldStyle(.roundedBorder)
            Button("Create trainer") {
                run {
                    try trading.setServerURL(serverURL)
                    try await trading.register(trainerName: trainerName)
                    try await trading.refreshInventory(from: companion)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || trainerName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trading.trainerName ?? "Trainer").font(.headline)
                    Text(trading.friendCode ?? "").font(.system(.caption, design: .monospaced))
                }
                Spacer()
                Button("Copy code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(trading.friendCode ?? "", forType: .string)
                }
                .controlSize(.small)
            }

            HStack {
                TextField("Friend code", text: $friendCode).textFieldStyle(.roundedBorder)
                Button("Add") {
                    run {
                        _ = try await trading.requestFriend(friendCode: friendCode.uppercased())
                        friendCode = ""
                    }
                }
                .disabled(busy || friendCode.isEmpty)
            }

            pendingRequests
            friends
            invitations
            if trading.activeTrade != nil { activeTrade }

            HStack {
                Text(trading.serverURL).lineLimit(1).truncationMode(.middle)
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Refresh") { run { await reload(throwing: true) } }
                    .controlSize(.small).disabled(busy)
            }
        }
    }

    @ViewBuilder
    private var pendingRequests: some View {
        let requests = trading.friendRequests.filter {
            $0.status == "pending" && $0.addresseeID == trading.trainerID
        }
        if !requests.isEmpty {
            Divider()
            Text("Friend requests").font(.caption).foregroundStyle(.secondary)
            ForEach(requests, id: \.id) { request in
                HStack {
                    Text(request.other.trainerName)
                    Spacer()
                    Button("Accept") { run { _ = try await trading.acceptFriend(requestID: request.id) } }
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var friends: some View {
        if !trading.friends.isEmpty {
            Divider()
            Text("Friends").font(.caption).foregroundStyle(.secondary)
            ForEach(trading.friends) { friend in
                HStack {
                    Text(friend.trainerName)
                    Spacer()
                    Button("Trade") {
                        run {
                            _ = try await trading.invite(friendCode: friend.friendCode)
                            message = "Invite sent to \(friend.trainerName)."
                        }
                    }
                    .controlSize(.small).disabled(busy)
                }
            }
        }
    }

    @ViewBuilder
    private var invitations: some View {
        let pending = trading.invites.filter { $0.status == "pending" }
        let ready = trading.invites.filter { $0.status == "accepted" }
        if !pending.isEmpty || !ready.isEmpty {
            Divider()
            Text("Trade invites").font(.caption).foregroundStyle(.secondary)
            ForEach(pending, id: \.id) { invite in
                HStack {
                    Text(invite.other.trainerName)
                    Spacer()
                    if invite.inviteeID == trading.trainerID {
                        Button("Accept") { run { _ = try await trading.acceptInvite(inviteID: invite.id) } }
                            .controlSize(.small)
                    } else {
                        Text("Waiting").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(ready, id: \.id) { invite in
                HStack {
                    Text(invite.other.trainerName)
                    Spacer()
                    Button("Open") {
                        run { try await trading.openTrade(tradeID: invite.tradeID, peer: invite.other) }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var activeTrade: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Trade with \(trading.activeTrade?.peer.trainerName ?? "friend")").font(.headline)
            if trading.heldInventory.isEmpty {
                Text("No graduated Pokémon available.").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Your Pokémon", selection: $selectedPokemonID) {
                    Text("Choose…").tag("")
                    ForEach(trading.heldInventory) { pokemon in
                        Text(pokemon.displayName).tag(pokemon.creatureID)
                    }
                }
                if trading.activeTrade?.localOffer == nil {
                    Button("Offer Pokémon") {
                        guard let pokemon = trading.heldInventory.first(where: { $0.creatureID == selectedPokemonID }) else { return }
                        run { try await trading.offer(pokemon) }
                    }
                    .disabled(selectedPokemonID.isEmpty || busy)
                }
            }
            if let peer = trading.activeTrade?.peerPokemon {
                Text("They offer: \(peer.displayName) · OG \(peer.originalTrainer.trainerName)")
            } else {
                Text("Waiting for their offer…").font(.caption).foregroundStyle(.secondary)
            }
            if trading.activeTrade?.manifestDigest != nil,
               trading.activeTrade?.localOffer != nil,
               trading.activeTrade?.peerPokemon != nil {
                Button("Confirm trade") { run { try await trading.confirm() } }
                    .buttonStyle(.borderedProminent).disabled(busy)
            }
            Text(trading.activeTrade?.status.rawValue.capitalized ?? "")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func reload(throwing: Bool = false) async {
        guard trading.trainerID != nil else { return }
        do {
            try await trading.refreshFriends()
            try await trading.refreshInvites()
            try await trading.refreshInventory(from: companion)
            try await trading.recoverReceipts()
        } catch {
            message = String(describing: error)
            if throwing { return }
        }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do { try await operation() }
            catch { message = String(describing: error) }
        }
    }
}
