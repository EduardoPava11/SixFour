import Foundation

/// COLOR ATLAS — on-device training telemetry (companion to AtlasTrainer.swift,
/// docs/ON-DEVICE-TRAINING.md spike).
///
/// A dependency-free, Sendable, fixed-capacity ring buffer of per-step training
/// records. Designed to be HELD by a future `@Observable` model and rendered by
/// a cell-grid widget (one cell per step, loss → cell value), so it is a plain
/// value type: copying a snapshot out of the training queue is one struct copy,
/// no locks, no reference semantics. `Step` is Codable for replay/export.
struct AtlasTrainingTelemetry: Sendable, Equatable {

    /// One training step's record — what the cell-grid widget renders.
    struct Step: Sendable, Codable, Equatable, Identifiable {
        /// 0-based step index within the run.
        var step: Int
        /// Bradley–Terry loss after this step's update.
        var loss: Float
        /// Wall-clock milliseconds for this step (graph run, GPU-synchronous).
        var msPerStep: Double

        var id: Int { step }
    }

    /// Maximum retained steps; older records are overwritten ring-wise.
    let capacity: Int

    private var slots: [Step] = []
    private var writeIndex = 0
    /// Total steps ever recorded (≥ `count`; the widget's progress denominator).
    private(set) var totalRecorded = 0

    init(capacity: Int = 256) {
        precondition(capacity > 0, "telemetry capacity must be positive")
        self.capacity = capacity
    }

    /// Record one step, overwriting the oldest record once at capacity.
    mutating func record(_ step: Step) {
        if slots.count < capacity {
            slots.append(step)
        } else {
            slots[writeIndex] = step
        }
        writeIndex = (writeIndex + 1) % capacity
        totalRecorded += 1
    }

    /// Retained record count (≤ capacity).
    var count: Int { slots.count }

    /// The most recently recorded step, if any.
    var latest: Step? {
        slots.isEmpty ? nil : slots[(writeIndex + capacity - 1) % capacity]
    }

    /// All retained records, oldest → newest (the widget's row order).
    var chronological: [Step] {
        if slots.count < capacity { return slots }
        return Array(slots[writeIndex...]) + Array(slots[..<writeIndex])
    }
}
