import AppKit
import SwiftUI

/// Explicit, isolated local playtest harness. Never starts usage readers, trading,
/// Keychain, login-item migration, update checks or production save writes.
@MainActor
enum GameplayPreview {
    private static var window: NSWindow?

    static func start() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("PokeTokenBar Gameplay Preview", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("companion-state.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            var state = CompanionState()
            state.language = .en
            state.installBaselineSet = true
            state.claimedTodayTokensByProvider = ["preview": 0]
            state.lastDate = "preview"
            state.usedSinceInstall = 30_000_000
            state.dex = [DexEntry(id: "preview-pikachu", baseID: 25, finalID: 25,
                                  chainOrder: [25], rarity: .common, caughtAt: Date(),
                                  nature: .jolly, names: [25: ["en": "Pikachu"]])]
            state.inventory[ItemKind.rareCandy.rawValue] = 3
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        }
        let store = CompanionStore(provider: PreviewPokemonProvider(), fileURL: url,
                                   dittoDisguiseRollingEnabled: false)
        let content = GameplayPreviewView(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Pokémon Progression — Sandbox"
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PreviewPokemonProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        switch baseSpeciesID {
        case 1:
            EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: [
                EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                    rarity: .common, names: [1: ["en": "Bulbasaur"], 2: ["en": "Ivysaur"], 3: ["en": "Venusaur"]])
        case 147:
            EvoLine(baseID: 147, tree: EvoNode(speciesID: 147, children: [
                EvoNode(speciesID: 148, children: [EvoNode(speciesID: 149, children: [])])]),
                    rarity: .rare, names: [147: ["en": "Dratini"], 148: ["en": "Dragonair"], 149: ["en": "Dragonite"]])
        default:
            EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []),
                    rarity: .common, names: [25: ["en": "Pikachu"]])
        }
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        [BaseSpecies(id: 1, captureRate: 255), BaseSpecies(id: 25, captureRate: 190),
         BaseSpecies(id: 147, captureRate: 45)]
    }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        try await baseSpeciesIndex().first { $0.id == id }
    }
}

@MainActor
private struct GameplayPreviewView: View {
    let store: CompanionStore
    @State private var nav = PopoverNavigation()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Local playtest · isolated save", systemImage: "testtube.2")
                .font(.headline).foregroundStyle(.orange)
            Text("Simulated tokens only. Your installed app, real usage and Pokémon are untouched.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("+100K tokens") { addTokens(100_000) }
                Button("+1M tokens") { addTokens(1_000_000) }
                Button("+25M tokens") { addTokens(25_000_000) }
            }
            .controlSize(.small)
            Picker("Page", selection: $nav.tab) {
                Text("Catch").tag(PopoverTab.home)
                Text("Train").tag(PopoverTab.train)
                Text("Shop").tag(PopoverTab.shop)
                Text("Bag").tag(PopoverTab.bag)
                Text("Owned").tag(PopoverTab.collection)
            }.pickerStyle(.segmented)
            Group {
                switch nav.tab {
                case .home:
                    VStack(alignment: .leading, spacing: 12) {
                        CompanionHeader(store: store)
                        Text("Mode: \(store.trainingMode.rawValue). Change it in Train.")
                        Text("The catching meter evolves your Pokémon and starts a fresh egg after completion. Train pauses that meter; Balanced splits tokens equally.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                case .train: TrainingView(store: store)
                case .shop: ShopView(store: store, nav: nav)
                case .bag: BagView(store: store, nav: nav)
                case .collection: CollectionView(store: store, navigation: nav)
                case .trade: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text("Preview data persists here. Close this window or quit this app to finish.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 420, height: 760)
    }

    private func addTokens(_ delta: Int) {
        let previous = store.state.claimedTodayTokensByProvider?["preview"] ?? 0
        store.update(todayTokensByProvider: ["preview": previous + delta], todayDate: "preview",
                     monthTotal: previous + delta, burnTier: .normal, limitWarning: false, hasUsageData: true)
        Task { await store.hatchIfNeeded() }
    }
}
