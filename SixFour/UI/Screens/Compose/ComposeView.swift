import SwiftUI

/// Composition editor. Today shows just the Metric organ slot (the only
/// slot whose trainer + on-device consumer both ship — see `OrganSlot`
/// in `Organs/Organ.swift` for the no-stubs rationale) plus the active
/// palette-algorithm blurb. The algorithm itself is picked on the capture screen.
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
                    LabeledContent("Algorithm", value: algorithmLabel)
                }

                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.up.right.circle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Palette algorithm lives on the capture screen")
                                .font(.subheadline.weight(.medium))
                            Text("K-means · Wu · Octree — the three per-frame extraction families.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(algorithmBlurb)
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
            extractorChoice: composition.extractorChoice
        )
    }

    private var algorithmLabel: String {
        composition.extractorChoice.label
    }

    private var algorithmBlurb: String {
        switch composition.extractorChoice {
        case .kMeans:
            return "Iterative Lloyd k-means on the GPU — adapts 256 centroids to the scene. Fastest; best for high-variance content."
        case .wu:
            return "Wu 1992 recursive variance-minimizing bipartition. Deterministic, globally variance-aware, and produces the richest per-cluster statistics for editing tools."
        case .octree:
            return "Hierarchical octree with count-based reduction to 256 leaves. Most predictable structure; best for flat-colored content."
        }
    }
}
