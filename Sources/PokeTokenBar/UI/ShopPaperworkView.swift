import SwiftUI

/// Optional comedy, deliberately isolated from ShopView's purchasing model.
@MainActor
struct ShopPaperworkView: View {
    @State private var expanded: Bool
    @State private var paperwork: ShopPaperwork

    // Initial values only; subsequent interaction belongs to this view instance.
    init(initiallyExpanded: Bool = false, initialPaperwork: ShopPaperwork = ShopPaperwork()) {
        _expanded = State(initialValue: initiallyExpanded)
        _paperwork = State(initialValue: initialPaperwork)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 9) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Psyduck’s Paperwork").font(.callout.weight(.medium))
                        Text("Free nonsense. No game effects.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Psyduck’s Paperwork")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Optional comedy. Does not affect purchases, tokens or Pokémon.")

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        // Static art only: no idle animation or attention-seeking timer.
                        SpriteView(speciesID: 54, size: 52, animated: false)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(paperwork.form.title)
                                .font(.callout.weight(.semibold))
                            Text(paperwork.line)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if paperwork.stage == .filed {
                        Text(paperwork.form.stamp)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.orange.opacity(0.65), lineWidth: 1.5))
                            .accessibilityLabel("Fictional certificate: \(paperwork.form.stamp)")
                    }

                    HStack {
                        Text("No authority. Plenty of forms.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button(paperwork.stage.action) { paperwork.advance() }
                            .controlSize(.small)
                            .accessibilityHint("Advances the fictional form. Does not buy or change anything in the game.")
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(.horizontal, 2)
    }
}
