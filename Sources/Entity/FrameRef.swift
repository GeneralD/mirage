/// One frame on the frame path: a leased surface plus its timing. Pixel storage
/// is referenced, never copied; the lease ends when the consumer releases the
/// token through `SurfaceRepository`.
public struct FrameRef: Sendable, Hashable {
    public let token: SurfaceToken
    public let descriptor: SurfaceDescriptor
    /// Presentation time on the host-time axis (see `HostTimestamp`).
    public let presentationTime: HostTimestamp

    public init(token: SurfaceToken, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) {
        self.token = token
        self.descriptor = descriptor
        self.presentationTime = presentationTime
    }
}
