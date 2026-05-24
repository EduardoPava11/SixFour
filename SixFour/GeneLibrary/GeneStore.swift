import Foundation
import os

/// On-disk catalog of organ files. Each organ lives under
/// `<appSupport>/SixFour/genes/<slot>/<hash>.<ext>` and is described in a
/// per-slot index file `<appSupport>/SixFour/genes/<slot>/index.json`.
///
/// AirDrop'd `.sixfour-genes` bundles are unpacked here by AirDropHandler.
actor GeneStore {
    static let log = Logger(subsystem: "com.sixfour.SixFour", category: "genes")

    private let root: URL
    private let fm = FileManager.default
    private(set) var descriptors: [OrganSlot: [OrganDescriptor]] = [:]
    private(set) var compositions: [Composition] = [.classicalBaseline]

    init() throws {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = support.appending(path: "SixFour/genes", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.root = dir
        for slot in OrganSlot.allCases {
            let slotDir = dir.appending(path: slot.rawValue, directoryHint: .isDirectory)
            try fm.createDirectory(at: slotDir, withIntermediateDirectories: true)
        }

        // Load indices inline — actor init can write to isolated state but cannot
        // call isolated methods (Swift 6).
        var newDescs: [OrganSlot: [OrganDescriptor]] = [:]
        for slot in OrganSlot.allCases {
            let indexURL = dir.appending(path: slot.rawValue).appending(path: "index.json")
            if fm.fileExists(atPath: indexURL.path) {
                let data = try Data(contentsOf: indexURL)
                newDescs[slot] = try JSONDecoder().decode([OrganDescriptor].self, from: data)
            } else {
                newDescs[slot] = []
            }
        }
        self.descriptors = newDescs

        let cIndex = dir.appending(path: "compositions.json")
        if fm.fileExists(atPath: cIndex.path) {
            let data = try Data(contentsOf: cIndex)
            let list = try JSONDecoder().decode([Composition].self, from: data)
            self.compositions = [.classicalBaseline] + list.filter { !$0.isBaseline }
        }
    }

    /// Re-read all on-disk indices. Useful after AirDrop import races the actor.
    func refresh() throws {
        var newDescs: [OrganSlot: [OrganDescriptor]] = [:]
        for slot in OrganSlot.allCases {
            let indexURL = root.appending(path: slot.rawValue).appending(path: "index.json")
            if fm.fileExists(atPath: indexURL.path) {
                let data = try Data(contentsOf: indexURL)
                let list = try JSONDecoder().decode([OrganDescriptor].self, from: data)
                newDescs[slot] = list
            } else {
                newDescs[slot] = []
            }
        }
        descriptors = newDescs

        let cIndex = root.appending(path: "compositions.json")
        if fm.fileExists(atPath: cIndex.path) {
            let data = try Data(contentsOf: cIndex)
            let list = try JSONDecoder().decode([Composition].self, from: data)
            compositions = [.classicalBaseline] + list.filter { !$0.isBaseline }
        }
    }

    func url(for descriptor: OrganDescriptor) -> URL {
        root.appending(path: descriptor.slot.rawValue).appending(path: descriptor.filename)
    }

    func addOrgan(descriptor: OrganDescriptor, content: Data) throws {
        let dest = url(for: descriptor)
        try content.write(to: dest)
        var slotList = descriptors[descriptor.slot] ?? []
        // Replace existing same-hash entry if present.
        slotList.removeAll { $0.hash == descriptor.hash }
        slotList.append(descriptor)
        descriptors[descriptor.slot] = slotList
        try writeIndex(slot: descriptor.slot, list: slotList)
    }

    func saveComposition(_ comp: Composition) throws {
        compositions.removeAll { $0.name == comp.name && !$0.isBaseline }
        compositions.append(comp)
        let payload = compositions.filter { !$0.isBaseline }
        let data = try JSONEncoder().encode(payload)
        try data.write(to: root.appending(path: "compositions.json"))
    }

    private func writeIndex(slot: OrganSlot, list: [OrganDescriptor]) throws {
        let data = try JSONEncoder().encode(list)
        try data.write(to: root.appending(path: slot.rawValue).appending(path: "index.json"))
    }

    // MARK: - Loading typed organs

    func loadMetric(named hash: String) -> MetricOrgan? {
        guard let d = descriptors[.metric]?.first(where: { $0.hash == hash }) else { return nil }
        return try? MetricOrgan(descriptor: d, fileURL: url(for: d))
    }
}
