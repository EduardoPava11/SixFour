import Foundation

/// Bounded accumulator for OKLabTiles produced by MetalPipeline.
/// Capacity matches SixFour's fixed 64-frame burst.
actor FrameBuffer {
    private(set) var frames: [OKLabTile] = []
    let capacity: Int

    init(capacity: Int = 64) {
        self.capacity = capacity
        frames.reserveCapacity(capacity)
    }

    /// Returns true if this tile filled the buffer (i.e. burst is complete).
    @discardableResult
    func append(_ tile: OKLabTile) -> Bool {
        guard frames.count < capacity else { return true }
        frames.append(tile)
        return frames.count == capacity
    }

    func snapshot() -> [OKLabTile] { frames }

    func reset() { frames.removeAll(keepingCapacity: true) }

    var count: Int { frames.count }
    var isFull: Bool { frames.count >= capacity }
}
