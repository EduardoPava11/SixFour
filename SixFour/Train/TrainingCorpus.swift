import Foundation

/// THE CORPUS EXPORT — the per-capture training-data bundle and its AirDrop
/// packaging (`Feature.trainingCorpus`).
///
/// The per-capture-learning plan (`docs/PER-CAPTURE-LEARNING-RESEARCH.md` §5.1)
/// and the shipped meta-init loader (`MetaInit.deployedW0`) both wait on ONE
/// missing thing: a corpus of REAL captures on the Mac. Until now every training
/// input the phone manufactures was computed and dropped at the burst seam — the
/// θ_up gene, the band-head result, the drained t-band pairs all died in memory,
/// and the raw burst survived only in the single overwritten
/// `sixfour_bundle.json`. This module persists them, per capture, next to the
/// GIF + `.s4cr` the shutter already writes, and stages the accumulated set into
/// one AirDroppable archive.
///
/// Two artifacts per capture (same stem as the GIF):
///
/// - **`sixfour_<stamp>.volume.npy`** — the burst as the interleaved OKLab Q16
///   volume, `int32`, shape `(frames, side, side, 3)`, C order, little-endian.
///   This is `CaptureGene.volume(from:)` — the SAME single sanctioned
///   float→device crossing the somatic trainer consumes — so the Mac retrains
///   from byte-identical inputs (zero train/deploy skew). Raw-volume-first is
///   deliberate: every derived feature (octant pairs, root-chart bands, any
///   future basis) can be re-manufactured from it with the shared kernels, so
///   the corpus survives model pivots.
/// - **`sixfour_<stamp>.train.json`** — the device's own training verdicts and
///   labels (Codable, the `CaptureBundle` house pattern): the shipped θ_up gene
///   (absent == the floor), the S_t band-head outcome, the per-slot certified
///   halt orders, and the drained t-band feature/target pairs exactly as the
///   on-device trainer saw them (the single exact→float boundary, pre-subsample).
///
/// The export half gathers every capture's artifacts (`.gif`, `.s4cr`,
/// `.volume.npy`, `.train.json`, `.contact.png`) into a manifest-carrying
/// folder and zips it with `NSFileCoordinator`'s `.forUploading` (an Apple
/// system facility — the zero-third-party rule stands). Mac-side reader:
/// `trainer/corpus_ingest.py`.
enum TrainingCorpus {

    /// Corpus schema identifier, written into both sidecar and manifest.
    static let sidecarSchema = "sixfour.corpus.capture/1"
    static let manifestSchema = "sixfour.corpus/1"

    // MARK: - Per-capture sidecar

    /// The S_t band-head outcome — a Codable mirror of
    /// `BandHeadTrainer.Result` plus the variance floor the verdict was read
    /// against (the YinYangCircuitTests convention).
    struct BandHeadOutcome: Sendable, Codable, Equatable {
        let initialMSE: Float
        let finalMSE: Float
        let weights: [Float]
    }

    /// The drained t-band supervised pairs — the yin ladder's manufactured
    /// labels, exactly as drained at burst end (features row-major,
    /// `pairs × width`). Persisted in full; the Mac subsamples as it pleases.
    struct TBandPairs: Sendable, Codable, Equatable {
        let width: Int
        let features: [Float]
        let targets: [Float]
    }

    /// The per-capture training sidecar (`sixfour_<stamp>.train.json`).
    /// Every field the burst did not produce is absent-as-nil, never invented
    /// (the `.s4cr` rule, in Codable form).
    struct Sidecar: Sendable, Codable {
        var schema: String = TrainingCorpus.sidecarSchema
        /// The shared artifact stem (`sixfour_<stamp>`), pairing this sidecar
        /// with its GIF / `.s4cr` / volume by name.
        var stem: String
        var capturedAt: Date
        /// Capture color pipeline tag (`CaptureSession.ActiveColorSpaceTag`).
        var colorSpace: String
        /// App build provenance (BuildStamp) — which kernels made this data.
        var buildSHA: String = BuildStamp.gitSHA
        var frames: Int
        var side: Int
        /// The volume artifact's filename, when written.
        var volumeFile: String?
        /// The shipped somatic gene (nil == the deterministic floor shipped;
        /// the gated-S rule already filtered non-working genes).
        var thetaUp: CaptureGene.ThetaUp?
        /// The S_t yang band-head training outcome (nil == skipped/starved).
        var bandHead: BandHeadOutcome?
        /// Per-slot certified kinematic orders (`ColorHead.haltFloor()`,
        /// 256 = the 16×16 region face; -1 = refused).
        var haltOrders: [Int32]?
        /// The manufactured t-band pairs (nil == ladder starved).
        var tband: TBandPairs?
    }

    // MARK: - Volume artifact

    /// Encode the burst tiles as the corpus volume `.npy` (int32 Q16 OKLab,
    /// shape `(frames, side, side, 3)`), reusing `CaptureGene.volume` — the
    /// sanctioned quantization — and the house `V21Npy` encoder. Nil where the
    /// burst is not octant-partitionable (the trainer's own precondition).
    static func volumeNpy(tiles: [OKLabTile]) -> Data? {
        guard let volume = CaptureGene.volume(from: tiles),
              let side = tiles.first?.side else { return nil }
        return V21Npy.encode(volume, shape: "(\(tiles.count), \(side), \(side), 3)")
    }

    /// `sixfour_<stamp>.volume.npy` beside the GIF.
    static func volumeURL(pairedWith gifURL: URL) -> URL {
        gifURL.deletingPathExtension()
            .appendingPathExtension("volume")
            .appendingPathExtension("npy")
    }

    /// `sixfour_<stamp>.train.json` beside the GIF.
    static func sidecarURL(pairedWith gifURL: URL) -> URL {
        gifURL.deletingPathExtension()
            .appendingPathExtension("train")
            .appendingPathExtension("json")
    }

    /// Atomic best-effort sidecar write (ISO-8601 dates so the Python reader
    /// needs no epoch convention).
    static func writeSidecar(_ sidecar: Sidecar, to url: URL) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        try (try enc.encode(sidecar)).write(to: url, options: .atomic)
    }

    // MARK: - The corpus archive (AirDrop packaging)

    /// The per-capture artifact suffixes staged into the archive, by stem.
    private static let artifactSuffixes = [
        ".gif", ".s4cr", ".volume.npy", ".train.json", ".contact.png",
    ]

    /// Stems (`sixfour_<stamp>`) of captures with a persisted volume — the
    /// corpus members. Sorted so the manifest is deterministic.
    static func corpusStems(in documents: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        return names.filter { $0.hasSuffix(".volume.npy") }
            .map { String($0.dropLast(".volume.npy".count)) }
            .sorted()
    }

    /// Stage every corpus capture into a fresh folder:
    /// `<into>/SixFour-corpus/` containing each stem's artifacts plus
    /// `corpus_manifest.json`. Returns the folder URL. Pure file copies —
    /// separated from `zipArchive` so tests can assert the staged contents.
    static func stageFolder(documents: URL, into scratch: URL) throws -> URL {
        let fm = FileManager.default
        let folder = scratch.appendingPathComponent("SixFour-corpus", isDirectory: true)
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let stems = corpusStems(in: documents)
        var staged: [String: [String]] = [:]
        for stem in stems {
            var files: [String] = []
            for suffix in artifactSuffixes {
                let name = stem + suffix
                let src = documents.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                try fm.copyItem(at: src, to: folder.appendingPathComponent(name))
                files.append(name)
            }
            staged[stem] = files
        }

        struct Manifest: Codable {
            let schema: String
            let createdAt: Date
            let buildSHA: String
            let captureCount: Int
            let captures: [String: [String]]
        }
        let manifest = Manifest(schema: manifestSchema, createdAt: Date(),
                                buildSHA: BuildStamp.gitSHA,
                                captureCount: stems.count, captures: staged)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        try (try enc.encode(manifest))
            .write(to: folder.appendingPathComponent("corpus_manifest.json"), options: .atomic)
        return folder
    }

    /// Zip a staged folder via `NSFileCoordinator` `.forUploading` (the system
    /// zips a directory read) and park the result at a stable scratch URL the
    /// share sheet can hold. Throws when coordination fails.
    static func zipArchive(of folder: URL, into scratch: URL) throws -> URL {
        let dest = scratch.appendingPathComponent(folder.lastPathComponent + ".zip")
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }

        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading,
                                       error: &coordError) { zipped in
            do { try fm.copyItem(at: zipped, to: dest) } catch { copyError = error }
        }
        if let coordError { throw coordError }
        if let copyError { throw copyError }
        return dest
    }

    /// The one-call export: stage + zip from Documents into the temporary
    /// directory. Returns nil (never throws into the UI) when the corpus is
    /// empty or packaging fails — the share button simply does not appear /
    /// logs. Blocking file I/O: call OFF the main actor.
    static func exportArchive() -> URL? {
        let fm = FileManager.default
        guard let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        let scratch = fm.temporaryDirectory
        guard !corpusStems(in: documents).isEmpty else { return nil }
        do {
            let folder = try stageFolder(documents: documents, into: scratch)
            return try zipArchive(of: folder, into: scratch)
        } catch {
            NSLog("TrainingCorpus export failed: \(String(describing: error))")
            return nil
        }
    }
}
