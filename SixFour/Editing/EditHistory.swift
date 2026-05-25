import Foundation

/// Bounded undo stack of render snapshots, extracted from `CaptureViewModel`.
///
/// Owns the array, the cap + eviction policy, and the best-effort background
/// file cleanup of dropped renders. It deliberately does NOT touch view-model
/// state: `undo()` returns the snapshot to restore and the view model applies
/// it to `primaryOutput` / `currentBundle` / `composition`. Keeping the stack
/// mechanics here shrinks the view model and makes the eviction policy unit
/// testable in isolation.
struct EditHistory {
    /// One render snapshot: the user-visible output plus the rich statistics
    /// that produced it, so a restore can re-apply both atomically.
    struct Entry: Sendable {
        let output: CaptureOutput
        let perFrameStatistics: [ClusterStatistics]
    }

    /// Initial render + 9 edits — covers the typical A/B/C compare flow
    /// without growing storage forever.
    static let cap = 10

    private(set) var entries: [Entry] = []

    /// True once there is at least one edit on top of the initial render.
    var canUndo: Bool { entries.count > 1 }

    /// Number of entries (initial render + edits). The review screen shows
    /// `count - 1` as the edit count.
    var count: Int { entries.count }

    /// Reset to a single initial entry — a fresh capture starts here.
    mutating func reset(to entry: Entry) {
        entries = [entry]
    }

    /// Push an edit. On overflow, evict the *second* entry (preserving the
    /// initial render at index 0 plus the most recent N-1 edits) and clean
    /// up its files.
    mutating func push(_ entry: Entry) {
        entries.append(entry)
        if entries.count > Self.cap {
            let evicted = entries.remove(at: 1)
            Self.deleteFiles(for: evicted.output)
        }
    }

    /// Pop the head and return the now-current entry to restore, or `nil` if
    /// already at the initial render (Retake is the way out of that state).
    /// Cleans up the popped render's files in the background.
    mutating func undo() -> Entry? {
        guard canUndo else { return nil }
        let popped = entries.removeLast()
        Self.deleteFiles(for: popped.output)
        return entries.last
    }

    /// Best-effort background cleanup of a dropped render's GIF + optional
    /// contact sheet. Errors are swallowed — the OS recycles Documents on
    /// next launch anyway, and Undo is supposed to feel instant.
    nonisolated static func deleteFiles(for output: CaptureOutput) {
        let gif = output.gifURL
        let contact = output.contactURL
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: gif)
            if let contact {
                try? FileManager.default.removeItem(at: contact)
            }
        }
    }
}
