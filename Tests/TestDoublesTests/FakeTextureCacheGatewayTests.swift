import Domain
import TestDoubles
import Testing

@Suite("FakeTextureCacheGateway", .timeLimit(.minutes(1)))
struct FakeTextureCacheGatewayTests {
    private let gateway = FakeTextureCacheGateway()
    private let context = FakeGPUContextHandle()
    private let surface = FakeSurfaceHandle(id: 1)

    @Test("a bind given back once is balanced")
    func balanced() throws {
        let texture = try gateway.bind(surface, on: context)
        #expect((texture as? FakeTextureHandle)?.surface === surface)
        #expect(gateway.liveCount == 1)

        try gateway.unbind(texture)

        #expect(gateway.bindCount == 1)
        #expect(gateway.unbindCount == 1)
        #expect(gateway.liveCount == 0)
        #expect(gateway.isBalanced)
    }

    @Test("a bind never given back is a visible mismatch")
    func leakIsVisible() throws {
        let kept = try gateway.bind(surface, on: context)
        try gateway.unbind(try gateway.bind(surface, on: context))

        #expect(gateway.bindCount == 2)
        #expect(gateway.unbindCount == 1)
        #expect(gateway.liveCount == 1)
        #expect(!gateway.isBalanced)
        try gateway.unbind(kept)
        #expect(gateway.isBalanced)
    }

    @Test("a second unbind of the same handle throws and is counted, not absorbed")
    func doubleUnbind() throws {
        let texture = try gateway.bind(surface, on: context)
        try gateway.unbind(texture)

        #expect(throws: GPUError.foreignHandle) { try gateway.unbind(texture) }

        #expect(gateway.doubleUnbindCount == 1)
        #expect(gateway.unbindCount == 1, "the double release is not an unbind")
        #expect(!gateway.isBalanced)
    }

    @Test("foreign surfaces, contexts and textures are refused as the live gateway refuses them")
    func provenance() {
        #expect(throws: SurfaceError.foreignHandle) { try gateway.bind(ForeignSurfaceHandle(), on: context) }
        #expect(throws: GPUError.foreignHandle) { try gateway.bind(surface, on: ForeignContextHandle()) }
        #expect(throws: GPUError.foreignHandle) { try gateway.unbind(ForeignTextureHandle()) }
        #expect(throws: SurfaceError.foreignHandle, "the surface is checked first, as in the live gateway") {
            try gateway.bind(ForeignSurfaceHandle(), on: ForeignContextHandle())
        }
        #expect(gateway.bindCount == 0)
        #expect(gateway.doubleUnbindCount == 0, "a foreign texture is not a double unbind")
    }

    @Test("a scripted bind failure leaves the counters untouched")
    func scriptedFailure() {
        gateway.failBind(with: .textureBindingFailed)
        #expect(throws: GPUError.textureBindingFailed) { try gateway.bind(surface, on: context) }
        #expect(gateway.bindCount == 0)
        #expect(gateway.liveCount == 0)
    }
}

private final class ForeignSurfaceHandle: SurfaceHandle, Sendable {
    var backing: AnyObject { self }
}
