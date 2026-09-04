import AppKit
import SwiftUI

@MainActor
private final class MagikarpFlapClock {
    private var timer: Timer?
    private var previous: Date?
    private var tick: (@MainActor (Double) -> Bool)?

    func start(framesPerSecond: Double, tick: @escaping @MainActor (Double) -> Bool) {
        guard timer == nil else { return }
        self.tick = tick
        previous = Date()
        let interval = 1 / framesPerSecond
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fire() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previous = nil
        tick = nil
    }

    private func fire() {
        guard timer != nil, let previous, let tick else { return }
        let now = Date()
        self.previous = now
        if !tick(now.timeIntervalSince(previous)) { stop() }
    }
}

@MainActor
struct MagikarpFlapView: View {
    let onClose: () -> Void

    @State private var game = MagikarpFlapGame()
    @State private var magikarpImage: NSImage?
    @State private var highScore: Int
    @State private var clock = MagikarpFlapClock()
    @FocusState private var boardFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let defaults: UserDefaults
    private static let highScoreKey = "magikarpFlapHighScore"

    init(onClose: @escaping () -> Void, defaults: UserDefaults = .standard) {
        self.onClose = onClose
        self.defaults = defaults
        _highScore = State(initialValue: defaults.integer(forKey: Self.highScoreKey))
        _magikarpImage = State(initialValue: SpriteLoader.cachedImage(speciesID: 129))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Magikarp Flap").font(.title3.weight(.bold))
                    Text("A heroic journey of several centimetres.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: onClose).controlSize(.small)
            }

            board
            .frame(height: 405)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
            .contentShape(Rectangle())
            .onTapGesture(perform: flap)
            .focusable()
            .focused($boardFocused)
            .onKeyPress(.space) {
                flap()
                return .handled
            }
            .accessibilityLabel("Magikarp Flap game")
            .accessibilityValue(statusText)
            .accessibilityHint("Click or press Space to make Magikarp flap upward.")

            HStack {
                Label("Click or Space to flap", systemImage: "hand.tap")
                Spacer()
                Text("Best \(highScore)").monospacedDigit()
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(height: 520, alignment: .top)
        .task {
            boardFocused = true
            if magikarpImage == nil { magikarpImage = await SpriteLoader.image(speciesID: 129) }
        }
        .onDisappear { clock.stop() }
    }

    private var board: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: [Color.cyan.opacity(0.72), Color.blue.opacity(0.82)],
                               startPoint: .top, endPoint: .bottom)
                waveBands(size)
                ForEach(game.gates) { gate in gateView(gate, in: size) }
                scoreView
                magikarp
                    .rotationEffect(.degrees(max(-22, min(28, -game.velocity * 38))))
                    .position(x: MagikarpFlapGame.fishX * size.width,
                              y: (1 - game.fishY) * size.height)
                phaseOverlay
            }
        }
    }

    private func waveBands(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Rectangle().fill(.white.opacity(0.06)).frame(height: size.height * 0.22)
            Rectangle().fill(.black.opacity(0.08)).frame(height: size.height * MagikarpFlapGame.floor)
        }
        .allowsHitTesting(false)
    }

    private func gateView(_ gate: MagikarpFlapGame.Gate, in size: CGSize) -> some View {
        let x = gate.x * size.width
        let upperHeight = max(0, (1 - gate.gapCenter - MagikarpFlapGame.gateGap / 2) * size.height)
        let lowerStart = (1 - gate.gapCenter + MagikarpFlapGame.gateGap / 2) * size.height
        let width = MagikarpFlapGame.gateWidth * size.width
        return ZStack(alignment: .topLeading) {
            pipe.frame(width: width, height: upperHeight).position(x: x, y: upperHeight / 2)
            pipe.frame(width: width, height: max(0, size.height - lowerStart))
                .position(x: x, y: lowerStart + max(0, size.height - lowerStart) / 2)
        }
        .allowsHitTesting(false)
    }

    private var pipe: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: [.green.opacity(0.9), .mint, .green.opacity(0.75)],
                                 startPoint: .leading, endPoint: .trailing))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.35), lineWidth: 2))
    }

    private var magikarp: some View {
        Group {
            if let magikarpImage {
                let fit = SpriteFit.size(for: magikarpImage.size, box: 54)
                Image(nsImage: magikarpImage).resizable().interpolation(.none)
                    .frame(width: fit.width, height: fit.height)
            } else {
                Text("🐟").font(.system(size: 42))
            }
        }
        .frame(width: 58, height: 54)
        .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
        .allowsHitTesting(false)
    }

    private var scoreView: some View {
        VStack {
            Text("\(game.score)").font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(.white).shadow(color: .black.opacity(0.35), radius: 2, y: 2)
                .monospacedDigit()
            Spacer()
        }
        .padding(.top, 14).allowsHitTesting(false)
    }

    @ViewBuilder
    private var phaseOverlay: some View {
        if game.phase != .running {
            VStack(spacing: 8) {
                Text(game.phase == .ready ? "Ready to flop?" : "Magikarp has flopped.")
                    .font(.headline)
                Text(game.phase == .ready ? "Click or press Space" : "Score \(game.score) · click to try again")
                    .font(.caption)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(false)
        }
    }

    private var statusText: String {
        switch game.phase {
        case .ready: "Ready. Best score \(highScore)."
        case .running: "Score \(game.score). Best score \(highScore)."
        case .gameOver: "Game over. Score \(game.score). Best score \(highScore)."
        }
    }

    private func flap() {
        game.flap()
        boardFocused = true
        clock.start(framesPerSecond: reduceMotion ? 20 : 30) { seconds in
            game.tick(seconds: seconds)
            if game.phase == .gameOver, game.score > highScore {
                highScore = game.score
                defaults.set(highScore, forKey: Self.highScoreKey)
            }
            return game.phase == .running
        }
    }
}
