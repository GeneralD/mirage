import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakePreviewGateway", .timeLimit(.minutes(1)))
struct FakePreviewGatewayTests {
    private let gateway = FakePreviewGateway()
    private let gpu = FakeGPUGateway()
    private let textures = FakeTextureCacheGateway()

    private struct Rig {
        let context: any GPUContextHandle
        let layer: any PreviewLayerHandle
        let texture: any TextureHandle
        let kernel: FakeLibraryHandle
    }

    private func rig() throws -> Rig {
        let context = try gpu.makeContext()
        let layer = try gateway.prepare(FakePreviewTargetHandle(), on: context)
        return Rig(
            context: context, layer: layer, texture: try textures.bind(FakeSurfaceHandle(id: 1), on: context),
            kernel: FakeLibraryHandle(source: "preview"))
    }

    @Test("prepare mints a fresh layer per call that remembers its target and context")
    func prepareMintsLayers() throws {
        let context = try gpu.makeContext()
        let target = FakePreviewTargetHandle()
        let first = try #require(try gateway.prepare(target, on: context) as? FakePreviewLayerHandle)
        let second = try #require(try gateway.prepare(target, on: context) as? FakePreviewLayerHandle)

        #expect(ObjectIdentifier(first.target) == ObjectIdentifier(target))
        #expect(ObjectIdentifier(first.context) == ObjectIdentifier(context))
        #expect(ObjectIdentifier(first) != ObjectIdentifier(second))
        #expect(gateway.prepared.values.map(ObjectIdentifier.init) == [ObjectIdentifier(first), ObjectIdentifier(second)])
    }

    @Test("prepare refuses a foreign target before a foreign context, and a scripted error after both")
    func prepareRefusals() throws {
        let context = try gpu.makeContext()
        #expect(throws: PreviewError.foreignTarget) { try gateway.prepare(ForeignTarget(), on: ForeignContext()) }
        #expect(throws: GPUError.foreignHandle) { try gateway.prepare(FakePreviewTargetHandle(), on: ForeignContext()) }

        gateway.failPrepare(with: GPUError.noDevice)
        #expect(throws: GPUError.noDevice) { try gateway.prepare(FakePreviewTargetHandle(), on: context) }
        gateway.failPrepare(with: nil)
        _ = try gateway.prepare(FakePreviewTargetHandle(), on: context)
        #expect(gateway.prepared.count == 1)
    }

    @Test("draws complete in the order the test chooses, each exactly once, verbatim")
    func drawsCompleteInAnyOrder() throws {
        let rig = try rig()
        let completed = Collector<Int>()
        let received = Collector<GPUCompletion>()
        try gateway.draw(rig.texture, with: rig.kernel, into: rig.layer, on: rig.context) {
            completed.append(1)
            received.append($0)
        }
        try gateway.draw(rig.texture, with: rig.kernel, into: rig.layer, on: rig.context) { _ in completed.append(2) }
        #expect(gateway.pending.map(\.id) == [1, 2])

        let fault = GPUCompletion(gpuStart: 1, gpuEnd: 2, error: RawGPUError(domain: "MTLCommandBufferErrorDomain", code: 5))
        let second = try #require(gateway.pending.last)
        let first = try #require(gateway.pending.first)
        #expect(gateway.complete(second))
        #expect(gateway.complete(first, with: fault))

        #expect(completed.values == [2, 1])
        #expect(received.values == [fault])
        #expect(gateway.pending.isEmpty)
        #expect(gateway.draws.count == 2)
    }

    @Test("a draw records the handles exactly as they were handed in")
    func drawRecordsHandles() throws {
        let rig = try rig()
        try gateway.draw(rig.texture, with: rig.kernel, into: rig.layer, on: rig.context) { _ in }
        let draw = try #require(gateway.draws.values.first)

        #expect(ObjectIdentifier(draw.texture) == ObjectIdentifier(rig.texture))
        #expect(ObjectIdentifier(draw.kernel) == ObjectIdentifier(rig.kernel))
        #expect(ObjectIdentifier(draw.layer) == ObjectIdentifier(rig.layer))
        #expect(ObjectIdentifier(draw.context) == ObjectIdentifier(rig.context))
    }

    @Test("completing a draw twice is a reported issue and returns false")
    func doubleCompletionIsRefused() throws {
        let rig = try rig()
        let completed = Collector<Void>()
        try gateway.draw(rig.texture, with: rig.kernel, into: rig.layer, on: rig.context) { _ in completed.append(()) }
        let draw = try #require(gateway.pending.first)
        gateway.complete(draw)

        let again = Collector<Bool>()
        withKnownIssue { again.append(gateway.complete(draw)) }
        #expect(again.values == [false])
        #expect(completed.count == 1)
    }

    @Test("foreign handles are refused in the live order, and a scripted error after them, before anything is recorded")
    func drawRefusals() throws {
        let rig = try rig()
        let draw = { (texture: any TextureHandle, kernel: any LibraryHandle, layer: any PreviewLayerHandle, context: any GPUContextHandle) in
            try gateway.draw(texture, with: kernel, into: layer, on: context) { _ in }
        }

        #expect(throws: GPUError.foreignHandle) { try draw(ForeignTexture(), ForeignLibrary(), ForeignLayer(), ForeignContext()) }
        #expect(throws: GPUError.foreignHandle) { try draw(ForeignTexture(), ForeignLibrary(), ForeignLayer(), rig.context) }
        #expect(throws: GPUError.foreignHandle) { try draw(ForeignTexture(), rig.kernel, ForeignLayer(), rig.context) }
        #expect(throws: PreviewError.foreignTarget) { try draw(rig.texture, rig.kernel, ForeignLayer(), rig.context) }

        gateway.failDraw(with: GPUError.encoderUnavailable)
        #expect(throws: GPUError.encoderUnavailable) { try draw(rig.texture, rig.kernel, rig.layer, rig.context) }
        #expect(gateway.draws.count == 0)
    }
}

private final class ForeignTarget: PreviewTargetHandle, Sendable {
    var backing: AnyObject { self }
}

private final class ForeignContext: GPUContextHandle, Sendable {
    var backing: AnyObject { self }
}

private final class ForeignTexture: TextureHandle, Sendable {
    var backing: AnyObject { self }
}

private final class ForeignLibrary: LibraryHandle, Sendable {
    var backing: AnyObject { self }
}

private final class ForeignLayer: PreviewLayerHandle, Sendable {
    var backing: AnyObject { self }
}
