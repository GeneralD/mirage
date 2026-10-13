import Metal
import Testing

/// The issue #4 runner probe, kept as a test: a device exists, it is in the
/// `mac2` family, and a kernel compiled from source runs a compute pass with
/// correct results. This is the floor every later GPU smoke suite stands on
/// (the `MetalGateway` suites of MVP-A included), and it is what the CI
/// `test-gpu` job proves on every PR.
///
/// Written against the `mac2` family only: the GitHub runner's "Apple
/// Paravirtual device" reports `supportsFamily(.apple7) == false`, so nothing
/// here depends on an Apple-family feature (.claude/rules/gpu-testing.md).
/// The kernel is a plain buffer fill — it can neither hang nor fault, so it
/// never risks the test process's Metal access.
@Suite("Metal device smoke", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct MetalDeviceSmokeTests {
    private static let fillKernel = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void fill(device uint *out [[buffer(0)]], uint gid [[thread_position_in_grid]]) {
            out[gid] = gid * 2u + 1u;
        }
        """

    @Test("the default device belongs to the mac2 family")
    func deviceIsMac2() throws {
        let device = try #require(MetalDeviceProbe.makeDevice())
        #expect(device.supportsFamily(.mac2))
    }

    @Test("a kernel compiled from source fills a buffer on the GPU")
    func computeFillFromSource() throws {
        let device = try #require(MetalDeviceProbe.makeDevice())
        let library = try device.makeLibrary(source: Self.fillKernel, options: nil)
        let function = try #require(library.makeFunction(name: "fill"))
        let pipeline = try device.makeComputePipelineState(function: function)

        let count = 256
        let buffer = try #require(device.makeBuffer(length: count * MemoryLayout<UInt32>.stride, options: .storageModeShared))
        let queue = try #require(device.makeCommandQueue())
        let commandBuffer = try #require(queue.makeCommandBuffer())
        let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        let threadsPerGroup = min(pipeline.maxTotalThreadsPerThreadgroup, count)
        encoder.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        #expect(commandBuffer.status == .completed)
        let written = Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt32.self), count: count))
        let expected = (0..<count).map { UInt32($0) * 2 + 1 }
        #expect(written == expected)
    }
}
