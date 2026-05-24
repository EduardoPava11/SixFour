import Foundation
import UniformTypeIdentifiers
import os

/// Import / export `.sixfour-genes` bundles.
///
/// A `.sixfour-genes` bundle is a directory containing:
///   - `manifest.json` — array of OrganDescriptor
///   - `<slot>/<filename>` — one file per organ (Core ML `.mlpackage` or JSON)
///   - `compositions.json` (optional) — array of Composition
///
/// On iOS the directory is typically tar'd before AirDrop; we tar/untar with libarchive-free
/// pure-Swift by zipping via FileManager → temp tar would require a 3rd-party lib.
/// For v1 we treat the bundle as a *directory* that arrives via UIDocumentPicker, and
/// we export as a zipped Data via the system's Compression framework.
enum AirDropHandler {
    static let log = Logger(subsystem: "com.sixfour.SixFour", category: "airdrop")

    static let bundleUTType = UTType(exportedAs: "com.sixfour.genes")

    /// Import an unpacked bundle directory at `url` into `store`.
    /// Returns the number of organs imported across all slots.
    static func importBundle(at url: URL, into store: GeneStore) async throws -> Int {
        let manifestURL = url.appending(path: "manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let descriptors = try JSONDecoder().decode([OrganDescriptor].self, from: data)

        var imported = 0
        for d in descriptors {
            let src = url.appending(path: d.slot.rawValue).appending(path: d.filename)
            let payload = try Data(contentsOf: src)
            try await store.addOrgan(descriptor: d, content: payload)
            imported += 1
        }

        // Optional compositions.
        let compURL = url.appending(path: "compositions.json")
        if FileManager.default.fileExists(atPath: compURL.path) {
            let cdata = try Data(contentsOf: compURL)
            let comps = try JSONDecoder().decode([Composition].self, from: cdata)
            for c in comps { try await store.saveComposition(c) }
        }

        return imported
    }

    /// Export a composition + its organs into a new directory at `dest`.
    /// Caller is responsible for AirDrop'ing the directory.
    static func exportBundle(
        composition: Composition,
        store: GeneStore,
        to dest: URL
    ) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for slot in OrganSlot.allCases {
            try fm.createDirectory(
                at: dest.appending(path: slot.rawValue),
                withIntermediateDirectories: true
            )
        }

        var descs: [OrganDescriptor] = []

        func copyOrgan(slot: OrganSlot, hash: String?) async throws {
            guard let hash else { return }
            let all = await store.descriptors[slot] ?? []
            guard let d = all.first(where: { $0.hash == hash }) else { return }
            let src = await store.url(for: d)
            let dst = dest.appending(path: slot.rawValue).appending(path: d.filename)
            if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
            try fm.copyItem(at: src, to: dst)
            descs.append(d)
        }

        try await copyOrgan(slot: .metric, hash: composition.metric)

        let manifest = try JSONEncoder().encode(descs)
        try manifest.write(to: dest.appending(path: "manifest.json"))

        let comp = try JSONEncoder().encode([composition])
        try comp.write(to: dest.appending(path: "compositions.json"))
    }
}
