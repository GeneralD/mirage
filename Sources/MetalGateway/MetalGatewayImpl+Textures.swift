/// `TextureCacheGateway` live implementation.
/// OS API: `MTLDevice.makeTexture(descriptor:iosurface:plane:)`,
/// `IOSurfaceGetWidth` / `IOSurfaceGetHeight`.
import Domain
import IOSurface
import Metal

extension MetalGatewayImpl: TextureCacheGateway {
    /// `bgra8Unorm` is the one format the frame path carries (`PixelFormat.bgra32`).
    /// `.shared` storage because the memory is the IOSurface's (epic #14, D5); the #15
    /// spike proved it on Apple silicon and the `test-gpu` job re-proves it on the runner.
    public func bind(_ surface: any SurfaceHandle, on context: any GPUContextHandle) throws -> any TextureHandle {
        let raw = try (surface.backing as? IOSurface).orThrow(SurfaceError.foreignHandle)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: IOSurfaceGetWidth(raw), height: IOSurfaceGetHeight(raw), mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let device = try context.commandQueue().device
        return TextureBox(try device.makeTexture(descriptor: descriptor, iosurface: raw, plane: 0).orThrow(GPUError.textureBindingFailed))
    }

    /// No OS call to make: the texture's storage goes with the handle's last reference.
    public func unbind(_ texture: any TextureHandle) throws {
        _ = try texture.metalTexture()
    }
}
