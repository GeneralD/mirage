import Dependencies
import Domain

/// Puts the "only send while a client streams" decision on top of the CMIO
/// gateway, so the gateway stays a pass-through the tests never need a device for.
// Executor-confined: every mutation runs on FrameExecutor.
public final class StreamOutputDataSourceImpl: @unchecked Sendable {
    @Dependency(\.streamOutputGateway) private var gateway
    @Dependency(\.frameExecutor) private var frameExecutor
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    /// The declared format while a client is streaming, `nil` otherwise. One
    /// optional instead of a flag plus a descriptor, so "streaming without a
    /// declared format" cannot be represented.
    private var streamingFormat: SurfaceDescriptor?

    public init() {}
}

extension StreamOutputDataSourceImpl: StreamOutput {
    public func start(
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws {
        try gateway.start(deviceName: ProductIdentity.displayName, descriptor: descriptor, frameRate: frameRate) { [weak self] event in
            guard let self else { return }
            frameExecutor.run {
                self.streamingFormat = event == .streamStarted ? descriptor : nil
                self.developerLog.record(.stream, "client stream \(event == .streamStarted ? "started" : "stopped")")
                onEvent(event)
            }
        }
    }

    /// A best-effort snapshot: the value is written on the executor and may be
    /// read from elsewhere (display, logging), never used to gate a send.
    public var isStreaming: Bool { streamingFormat != nil }

    public func send(_ surface: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) -> SendOutcome {
        guard let declared = streamingFormat else { return .dropped(.noClient) }
        guard declared.matchesGeometry(of: descriptor) else {
            errorLog.record(
                .stream, "frame dropped: \(descriptor.width)x\(descriptor.height) does not match the declared \(declared.width)x\(declared.height)")
            return .dropped(.formatMismatch)
        }
        do {
            try gateway.send(surface, presentationTime: presentationTime)
            return .sent
        } catch {
            let code = Self.code(of: error)
            errorLog.record(.stream, "stream send failed: \(error) (code \(code))")
            return .dropped(.sendFailed(code: code))
        }
    }

    /// The raw code a failed sample-buffer build carries; `-1` for any other failure.
    private static func code(of error: any Error) -> Int {
        guard case .sampleBufferFailed(let code)? = error as? StreamOutputError else { return -1 }
        return code
    }
}
