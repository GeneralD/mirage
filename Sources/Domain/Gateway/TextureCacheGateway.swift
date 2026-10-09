import Dependencies

/// Thin pass-through from a pooled surface to a kernel-addressable texture.
/// Which surface to bind, when, and that every bind is unbound exactly once are
/// `GPURenderDataSource`'s invariants (checked against the fake's counters).
public protocol TextureCacheGateway: Sendable {
    /// A BGRA texture over plane 0 of the surface, readable and writable by
    /// kernels, sharing the surface's memory (no copy). `SurfaceError.foreignHandle`
    /// for a surface another gateway produced.
    func bind(_ surface: any SurfaceHandle, on context: any GPUContextHandle) throws -> any TextureHandle
    /// Gives a texture back through the port that issued it. The live gateway
    /// holds no state, so this validates provenance (`GPUError.foreignHandle`)
    /// and the storage goes with the handle's last reference; the fake counts.
    func unbind(_ texture: any TextureHandle) throws
}

public enum TextureCacheGatewayKey: TestDependencyKey {
    public static let testValue: any TextureCacheGateway = UnimplementedTextureCacheGateway()
}

extension DependencyValues {
    public var textureCacheGateway: any TextureCacheGateway {
        get { self[TextureCacheGatewayKey.self] }
        set { self[TextureCacheGatewayKey.self] = newValue }
    }
}

private struct UnimplementedTextureCacheGateway: TextureCacheGateway {
    func bind(_ surface: any SurfaceHandle, on context: any GPUContextHandle) throws -> any TextureHandle {
        reportIssue("TextureCacheGateway.bind not implemented")
        throw GPUError.textureBindingFailed
    }

    func unbind(_ texture: any TextureHandle) throws {
        reportIssue("TextureCacheGateway.unbind not implemented")
        throw GPUError.foreignHandle
    }
}
