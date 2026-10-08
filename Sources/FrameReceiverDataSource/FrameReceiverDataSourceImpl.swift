import Dependencies
import Domain

/// Extension side of the Mach link: registers the service name, owns the
/// receive loop (one `receive` per message) and decides when the host is gone.
///
/// The loop lives here, not in the gateway, so it can be driven message by
/// message in tests and so a blocked `mach_msg` never sits on the cooperative
/// pool: `stop()` destroys the receive right and the pending receive ends with
/// `.portDied`.
public final class FrameReceiverDataSourceImpl: @unchecked Sendable {
    @Dependency(\.machBootstrapGateway) var bootstrap
    @Dependency(\.machMessageGateway) var machMessage
    @Dependency(\.ioSurfaceGateway) var ioSurface
    @Dependency(\.frameExecutor) var frameExecutor
    @Dependency(\.continuousClock) var clock
    @Dependency(\.errorLog) var errorLog
    @Dependency(\.developerLog) var developerLog

    let frameGap: Duration

    // Executor-confined: every mutation runs on FrameExecutor.
    /// Time since the last frame, measured on the injected clock. A closure
    /// because the clock is an existential whose `Instant` cannot be stored.
    var sinceLastFrame: (@Sendable () -> Duration)?
    var hostPresent = false
    /// The receive right, kept so `stop()` can reach it from any context.
    var receiveRight: MachPortToken?
    /// A `start` is between its first line and its end. Lets `stop()` tell
    /// "start has not stored its right yet" from "nothing is running".
    var starting = false
    /// `stop()` arrived while `start` was still registering, so there was no
    /// right to destroy yet; `start` honours it before it begins receiving.
    var stopRequested = false

    /// - Parameter frameGap: silence longer than this means the host stalled.
    public init(frameGap: Duration = .seconds(2)) {
        self.frameGap = frameGap
    }
}

extension FrameReceiverDataSourceImpl: FrameReceiver {
    public func start(
        onFrame: @escaping @Sendable (IncomingSurface) -> Void,
        onEvent: @escaping @Sendable (ReceiverEvent) -> Void
    ) async throws {
        // Queued first, so a `stop()` issued from here on is remembered.
        frameExecutor.run { [self] in starting = true }
        let port: MachPortToken
        do {
            port = try registerService()
        } catch {
            frameExecutor.run { [self] in reset() }
            throw error
        }
        guard await claim(port) else { return }
        onEvent(.listening)
        // Cancelling `start` must also unblock the pending receive.
        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [self] in await receiveLoop(on: port, onFrame: onFrame, onEvent: onEvent) }
                group.addTask { [self] in await watchHost(onEvent: onEvent) }
                // The watchdog only returns once cancelled, so the first result
                // is the receive loop ending (or the whole task being cancelled).
                await group.next()
                group.cancelAll()
            }
        } onCancel: {
            stop()
        }
        frameExecutor.run { [self] in reset() }
    }

    public func stop() {
        frameExecutor.run { [self] in requestStop() }
    }
}

extension FrameReceiverDataSourceImpl {
    /// Runs on the executor. Destroys the right, or, when `start` has not
    /// stored one yet, leaves a note for `start` so the stop is not lost.
    private func requestStop() {
        guard receiveRight != nil else {
            stopRequested = starting
            return
        }
        destroyReceiveRight()
    }

    /// Stores the right on the executor and reports whether `start` may go on
    /// receiving; `false` means `stop()` got in first, so the right is destroyed
    /// here instead of leaving `start` blocked on a receive nobody will end.
    private func claim(_ port: MachPortToken) async -> Bool {
        await withCheckedContinuation { continuation in
            frameExecutor.run { [self] in
                guard !stopRequested else {
                    bootstrap.destroyReceiveRight(port)
                    reset()
                    continuation.resume(returning: false)
                    return
                }
                receiveRight = port
                continuation.resume(returning: true)
            }
        }
    }

    /// Runs on the executor.
    func destroyReceiveRight() {
        guard let port = receiveRight else { return }
        receiveRight = nil
        bootstrap.destroyReceiveRight(port)
    }

    /// Runs on the executor. Leaves the object ready for another `start`.
    private func reset() {
        destroyReceiveRight()
        hostPresent = false
        sinceLastFrame = nil
        starting = false
        stopRequested = false
    }

    /// `checkIn` first (the launchd-known name); `register` only as the
    /// fallback. Both raw codes are kept: they are the evidence for which
    /// route the sandboxed extension is allowed to use.
    private func registerService() throws -> MachPortToken {
        do {
            return try bootstrap.checkIn(serviceName: ProductIdentity.machServiceName)
        } catch let checkInError {
            developerLog.record(.receiver, "checkIn failed (\(checkInError)); falling back to register")
            do {
                return try bootstrap.register(serviceName: ProductIdentity.machServiceName)
            } catch let registerError {
                errorLog.record(.receiver, "service registration failed: checkIn \(checkInError), register \(registerError)")
                throw registerError
            }
        }
    }
}
