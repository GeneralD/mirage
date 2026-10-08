import Combine
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

    /// The started stream, owned here rather than in the gateway. Written once
    /// by `start` (extension launch, off the executor) and read by `send` on the
    /// executor; a subject so that hand-over needs no lock of its own.
    private let handle = CurrentValueSubject<(any StreamOutputHandle)?, Never>(nil)
    /// The declared format while at least one client is streaming, `nil`
    /// otherwise. One optional instead of a flag plus a descriptor, so
    /// "streaming without a declared format" cannot be represented. A subject
    /// rather than a bare `var` so `isStreaming` reads a whole value from any
    /// context (the subject synchronizes its `value`); the executor is its only writer.
    private let streamingFormat = CurrentValueSubject<SurfaceDescriptor?, Never>(nil)
    /// CMIO reports a start and a stop per client (Zoom and QuickTime at once
    /// are two), so the stream is live from the first start to the last stop.
    private var streamingClients = 0

    public init() {}
}

extension StreamOutputDataSourceImpl: StreamOutput {
    public func start(
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws {
        handle.value = try gateway.start(deviceName: ProductIdentity.displayName, descriptor: descriptor, frameRate: frameRate) {
            [weak self] event in
            guard let self else { return }
            // The executor block runs once and is gone; the strong capture lasts only that long.
            frameExecutor.run { [self] in
                streamingClients = max(0, streamingClients + (event == .streamStarted ? 1 : -1))
                streamingFormat.value = streamingClients > 0 ? descriptor : nil
                developerLog.record(.stream, "client stream \(event == .streamStarted ? "started" : "stopped"); \(streamingClients) streaming")
                onEvent(event)
            }
        }
    }

    /// A snapshot for display and logging; `send` decides on the executor.
    public var isStreaming: Bool { streamingFormat.value != nil }

    public func send(_ surface: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) -> SendOutcome {
        guard let declared = streamingFormat.value else { return .dropped(.noClient) }
        guard declared.matchesGeometry(of: descriptor) else {
            errorLog.record(
                .stream, "frame dropped: \(descriptor.width)x\(descriptor.height) does not match the declared \(declared.width)x\(declared.height)")
            return .dropped(.formatMismatch)
        }
        do {
            try handle.value.orThrow(StreamOutputError.notStarted).send(surface, presentationTime: presentationTime)
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
