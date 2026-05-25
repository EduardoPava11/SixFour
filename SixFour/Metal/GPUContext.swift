import Metal

/// Shared GPU plumbing for one Metal compute pipeline: a device, a *labeled*
/// command queue, and the default shader library.
///
/// Each SixFour palette pipeline (k-means, Wu, Octree) owns its own
/// `GPUContext` with a distinct queue label ("palette-kmeans", "palette-wu",
/// "palette-octree"). The labels surface in Instruments and the Metal frame
/// debugger, so GPU work is attributable per algorithm — the whole point of
/// giving each algorithm its own pipeline. The capture pipeline
/// (`MetalPipeline`) keeps its own device/queue inline; these contexts are for
/// the extraction pipelines.
///
/// One physical GPU backs all contexts (`MTLCreateSystemDefaultDevice` returns
/// the same device); separate command queues just give independent, labeled
/// command streams.
struct GPUContext {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let library: any MTLLibrary

    enum GPUContextError: Error {
        case noDevice, noQueue, noLibrary
        case missingKernel(String)
    }

    init(queueLabel: String) throws {
        guard let dev = MTLCreateSystemDefaultDevice() else { throw GPUContextError.noDevice }
        guard let q = dev.makeCommandQueue() else { throw GPUContextError.noQueue }
        guard let lib = dev.makeDefaultLibrary() else { throw GPUContextError.noLibrary }
        q.label = queueLabel
        self.device = dev
        self.queue = q
        self.library = lib
    }

    /// Build a compute pipeline state for a named kernel in the default library.
    func pso(_ name: String) throws -> any MTLComputePipelineState {
        guard let fn = library.makeFunction(name: name) else {
            throw GPUContextError.missingKernel(name)
        }
        return try device.makeComputePipelineState(function: fn)
    }
}
