import SwiftUI

/// Composition editor. Today shows just the Metric organ slot (the only
/// slot whose trainer + on-device consumer both ship — see `OrganSlot`
/// in `Organs/Organ.swift` for the no-stubs rationale) plus the active
/// palette mode blurb. The mode itself is picked on the capture screen.
struct ComposeView: View {
    let store: GeneStore
    @Binding var composition: Composition
    @Environment(\.dismiss) private var dismiss

    @State private var metricOrgans: [OrganDescriptor] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Active composition") {
                    LabeledContent("Name", value: composition.name)
                    LabeledContent("Metric", value: composition.metric ?? "—")
                    LabeledContent("Mode",   value: modeLabel)
                }

                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.up.right.circle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Palette mode lives on the capture screen")
                                .font(.subheadline.weight(.medium))
                            Text("Per-frame · Shared · Global — the three honest endpoints of the Sinkhorn spectrum.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(paletteModeBlurb)
                }

                Section("Metric") {
                    Button("Use baseline (no organ)") {
                        update(metric: nil)
                    }
                    ForEach(metricOrgans, id: \.hash) { d in
                        Button {
                            update(metric: d.hash)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(d.name).font(.body)
                                Text("gen \(d.generation) · \(d.hash.prefix(8))")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Compose")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refresh() }
        }
    }

    private func refresh() async {
        let snap = await store.descriptors
        metricOrgans = snap[.metric] ?? []
    }

    private func update(metric hash: String?) {
        composition = Composition(
            name: "custom",
            metric: hash,
            createdAt: Date(),
            paletteMode: composition.paletteMode
        )
    }

    private var modeLabel: String {
        switch composition.paletteMode {
        case .perFrame: return "Per-frame · θ = 0"
        case .shared:   return "Shared · θ ≈ 0.05"
        case .global:   return "Global · θ → ∞"
        }
    }

    private var paletteModeBlurb: String {
        switch composition.paletteMode {
        case .perFrame:
            return "Each frame carries its own 256-color palette. Larger files, sharpest per-frame detail. (Endpoint θ = 0, MATH.md Theorem 1.)"
        case .shared:
            return "One 256-color palette across all 64 frames at θ ≈ 0.05 (direct-exp Sinkhorn). Compact files, smooth motion, still preserves highlight/shadow contrast. (Endpoint §3.bis.)"
        case .global:
            return "One 256-color palette at θ → ∞ via log-domain Sinkhorn — the rank-1 limit. Most uniform across frames. (Endpoint Theorem 2.)"
        }
    }
}
