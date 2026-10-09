import IOSurface
import Metal
import Testing

/// Issue #15, first commit: does an IOSurface-backed `MTLTexture` work on the
/// CI runner's paravirtual device? `MetalGateway` binds frames with
/// `makeTexture(descriptor:iosurface:plane:)` (epic #14, D5) and cannot branch
/// on the storage mode, so this spike runs the same compute fill once per
/// candidate mode and reads the pixels back through the IOSurface. The mode
/// that passes here on both CI and a real Mac is the one the gateway hardcodes;
/// the spike is replaced by the `MetalGateway smoke` suite in the same PR.
@Suite("IOSurface texture spike", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct IOSurfaceTextureSpikeTests {
    private static let fillKernel = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void fill(texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
            out.write(float4(1.0, 0.5, 0.25, 1.0), gid);
        }
        """

    private static let side = 256

    private static func makeSurface() throws -> IOSurface {
        try #require(
            IOSurface(properties: [
                .width: side, .height: side, .bytesPerElement: 4, .pixelFormat: 0x4247_5241, .bytesPerRow: side * 4,
            ]))
    }

    @Test("a compute kernel writes into an IOSurface-backed texture", arguments: [MTLStorageMode.shared, .managed])
    func computeWritesThroughIOSurface(storageMode: MTLStorageMode) throws {
        let device = try #require(MetalDeviceProbe.makeDevice())
        let surface = try Self.makeSurface()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: Self.side, height: Self.side, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = storageMode
        let texture = try #require(device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0))

        let library = try device.makeLibrary(source: Self.fillKernel, options: nil)
        let pipeline = try device.makeComputePipelineState(function: try #require(library.makeFunction(name: "fill")))
        let queue = try #require(device.makeCommandQueue())
        let commandBuffer = try #require(queue.makeCommandBuffer())
        let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.dispatchThreadgroups(
            MTLSize(width: Self.side / 16, height: Self.side / 16, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        #expect(commandBuffer.status == .completed)
        #expect(commandBuffer.error == nil)

        IOSurfaceLock(surface, .readOnly, nil)
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }
        let base = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
        let stride = IOSurfaceGetBytesPerRow(surface)
        // bgra8Unorm: float4(1.0, 0.5, 0.25, 1.0) is stored as B G R A = 64 128 255 255.
        let expected: [UInt8] = [64, 128, 255, 255]
        let corners = [(0, 0), (Self.side - 1, 0), (0, Self.side - 1), (Self.side - 1, Self.side - 1), (Self.side / 2, Self.side / 2)]
        for (x, y) in corners {
            let pixel = (0..<4).map { base[y * stride + x * 4 + $0] }
            #expect(pixel == expected, "pixel (\(x), \(y)) under \(storageMode)")
        }
    }
}
