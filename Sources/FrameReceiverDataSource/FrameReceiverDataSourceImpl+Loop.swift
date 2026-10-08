import Dependencies
import Domain

extension FrameReceiverDataSourceImpl {
    /// Receives until the right dies or the receive fails. Returns normally in
    /// both cases: the caller treats "loop over" as the end of `start`.
    func receiveLoop(
        on port: MachPortToken,
        onFrame: @escaping @Sendable (IncomingSurface) -> Void,
        onEvent: @escaping @Sendable (ReceiverEvent) -> Void
    ) async {
        while let message = await nextMessage(on: port, onEvent: onEvent) {
            deliver(message, onFrame: onFrame, onEvent: onEvent)
        }
    }

    /// `nil` ends the loop: the right was destroyed (`stop()`), or the receive
    /// failed and the host has been reported lost.
    private func nextMessage(on port: MachPortToken, onEvent: @Sendable (ReceiverEvent) -> Void) async -> FrameMessage? {
        do {
            return try await machMessage.receive(on: port)
        } catch MachError.portDied {
            developerLog.record(.receiver, "receive right destroyed; receive loop ends")
            return nil
        } catch {
            errorLog.record(.receiver, "receive failed: \(error)")
            onEvent(.hostLost(.receiveFailed(code: Self.code(of: error))))
            return nil
        }
    }

    /// Resolves the surface off the executor (it only touches the kernel), then
    /// hands the frame over on it so `onFrame` and the presence state share
    /// one serial context.
    private func deliver(
        _ message: FrameMessage,
        onFrame: @escaping @Sendable (IncomingSurface) -> Void,
        onEvent: @escaping @Sendable (ReceiverEvent) -> Void
    ) {
        do {
            let incoming = IncomingSurface(
                handle: try ioSurface.resolve(message.surface),
                descriptor: message.descriptor,
                presentationTime: message.presentationTime
            )
            frameExecutor.run { [self] in
                noteHostPresent(onEvent: onEvent)
                sinceLastFrame = Self.stopwatch(on: clock)
                onFrame(incoming)
            }
        } catch {
            errorLog.record(.receiver, "frame dropped: surface did not resolve: \(error)")
            onEvent(.frameDropped(.sendFailed(code: Self.code(of: error))))
        }
    }

    /// Runs on the executor.
    private func noteHostPresent(onEvent: @Sendable (ReceiverEvent) -> Void) {
        guard !hostPresent else { return }
        hostPresent = true
        onEvent(.hostConnected)
    }

    /// Declares the host lost when no frame arrived for `frameGap`. Sleeps on
    /// the injected clock, so a test moves time by hand.
    func watchHost(onEvent: @escaping @Sendable (ReceiverEvent) -> Void) async {
        while (try? await clock.sleep(for: frameGap)) != nil {
            frameExecutor.run { [self] in checkGap(onEvent: onEvent) }
        }
    }

    /// Runs on the executor.
    private func checkGap(onEvent: @Sendable (ReceiverEvent) -> Void) {
        guard hostPresent, let silence = sinceLastFrame?(), silence >= frameGap else { return }
        hostPresent = false
        onEvent(.hostLost(.frameGap(frameGap)))
    }

    /// Starts a stopwatch on `clock`. Generic so the clock existential is opened
    /// and its `Instant` can live in the closure.
    private static func stopwatch<C: Clock>(on clock: C) -> @Sendable () -> Duration where C.Duration == Duration {
        let mark = clock.now
        return { mark.duration(to: clock.now) }
    }

    /// The raw code to log; errors without one report `-1`, as the Domain
    /// `Unimplemented*` doubles do.
    private static func code(of error: any Error) -> Int {
        guard case MachError.receiveFailed(let code) = error else { return -1 }
        return code
    }
}
