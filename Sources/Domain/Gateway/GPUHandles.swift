/// Opaque references to the GPU objects `MetalGateway` mints, in the shape of
/// `SurfaceHandle`: `backing` is the OS object typed as `AnyObject`, the gateway
/// that produced the handle casts it back and throws `GPUError.foreignHandle`
/// for anything else. No registry maps IDs to objects; the handle *is* the
/// reference, and ARC ends the object's life with the handle's last owner.

/// A device plus the command queue every pass is committed to.
public protocol GPUContextHandle: AnyObject, Sendable {
    var backing: AnyObject { get }
}

/// One compiled effect, resolved to its entry kernel and ready to dispatch
/// (live: the compute pipeline state). `EffectRuntimeRepository` caches these.
public protocol LibraryHandle: AnyObject, Sendable {
    var backing: AnyObject { get }
}

/// A surface made readable and writable by kernels (live: an IOSurface-backed
/// `MTLTexture`). It keeps the surface alive until it is unbound and dropped.
public protocol TextureHandle: AnyObject, Sendable {
    var backing: AnyObject { get }
}
