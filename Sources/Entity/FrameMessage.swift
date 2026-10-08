/// The wire contract between host and extension: one message per frame,
/// carrying the surface's send right (moved) and the metadata the receiver
/// cannot read from the surface itself. The Mach gateway on each side maps it
/// to and from the fixed C layout.
public struct FrameMessage: Sendable, Hashable {
    public let surface: MachSendRight
    public let descriptor: SurfaceDescriptor
    public let presentationTime: HostTimestamp

    public init(surface: MachSendRight, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) {
        self.surface = surface
        self.descriptor = descriptor
        self.presentationTime = presentationTime
    }
}
