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
                    LabeledContent("Algorithm", value: "Wu + K-means")
                    LabeledContent("Dither", value: composition.ditherMethod.label)
                }

                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quality-first palette")
                                .font(.subheadline.weight(.medium))
                            Text("Every GIF uses Wu-initialized k-means — the research quality leader — then your chosen dither, on the capture screen.")
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
            ditherMethod: composition.ditherMethod
        )
    }

    private var algorithmBlurb: String {
        "Wu-initialized k-means (Celebi 2011): Wu's variance boxes seed the GPU "
        + "Lloyd loop, the literature's near-optimal quantizer. Each of the 64 "
        + "frames keeps its own complete 256-colour palette (a full 64³ voxel "
        + "volume, no empty slots)."
    }
}
