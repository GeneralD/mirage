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
            switch message {
            case .frame(let frame):
                deliver(frame, onFrame: onFrame, onEvent: onEvent)
            case .hello(let right):
                // Through the executor: presence state is executor-confined and a hello must not
                // overtake the frames this loop queued before it.
                frameExecutor.run { [self] in adopt(presence: right, notifying: port) }
            case .deadName(let name):
                frameExecutor.run { [self] in noteDeadName(name, onEvent: onEvent) }
            case .notice:
                break
            }
        }
    }

    /// `nil` ends the loop: the right was destroyed (`stop()`), or the receive
    /// failed and the host has been reported lost.
    private func nextMessage(on port: MachPortToken, onEvent: @escaping @Sendable (ReceiverEvent) -> Void) async -> IncomingMessage? {
        do {
            return try await machMessage.receive(on: port)
        } catch MachError.portDied {
            developerLog.record(.receiver, "receive right destroyed; receive loop ends")
            return nil
        } catch {
            errorLog.record(.receiver, "receive failed: \(error)")
            let code = Self.code(of: error)
            // Through the executor: the frames this loop queued earlier have not
            // run yet, and the loss must not overtake their `hostConnected`.
            frameExecutor.run { [self] in
                hostPresent = false
                awaitingFirstHost = false
                onEvent(.hostLost(.receiveFailed(code: code)))
            }
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
            let code = Self.code(of: error)
            frameExecutor.run { onEvent(.frameDropped(.sendFailed(code: code))) }
        }
    }

    /// Runs on the executor. A new hello means a new host replaced the old one:
    /// the earlier right is given back before the new one is watched.
    private func adopt(presence right: MachSendRight, notifying servicePort: MachPortToken) {
        releasePresence()
        // A hello is not a frame: a host that greets and then stays silent (permission denied, hung at
        // launch) must still be declared lost, so the startup wait stays armed and only restarts its count.
        if awaitingFirstHost { sinceLastFrame = Self.stopwatch(on: clock) }
        presence = right
        do {
            try bootstrap.requestDeadNameNotification(of: right, to: servicePort)
            developerLog.record(.receiver, "hello received, watching presence right \(right.name)")
        } catch {
            // The frame gap still covers this host; only the prompt path is lost.
            errorLog.record(.receiver, "dead-name request failed: \(error)")
            releasePresence()
        }
    }

    /// Runs on the executor. Only the name of the right this receiver holds is
    /// trusted; any other name is ignored and nothing is deallocated for it.
    private func noteDeadName(_ name: MachPortToken, onEvent: @Sendable (ReceiverEvent) -> Void) {
        guard name.name == presence?.name else {
            developerLog.record(.receiver, "dead-name notification for unknown name \(name.name) ignored")
            return
        }
        hostPresent = false
        awaitingFirstHost = false
        onEvent(.hostLost(.deadName))
        presence = nil
        bootstrap.releaseDeadName(name)
    }

    /// Runs on the executor. Gives back the held presence right, if any.
    func releasePresence() {
        guard let held = presence else { return }
        presence = nil
        bootstrap.deallocate(MachPortToken(name: held.name))
    }

    /// Runs on the executor.
    private func noteHostPresent(onEvent: @Sendable (ReceiverEvent) -> Void) {
        awaitingFirstHost = false
        guard !hostPresent else { return }
        hostPresent = true
        onEvent(.hostConnected)
    }

    /// Declares the host lost when no frame arrived for `frameGap`, counted from
    /// the last frame, or from `start` while no host has been seen yet. Checks every
    /// quarter of the gap (worst-case detection latency 1.25 x `frameGap`) on
    /// the injected clock, so a test moves time by hand.
    func watchHost(onEvent: @escaping @Sendable (ReceiverEvent) -> Void) async {
        while (try? await clock.sleep(for: frameGap / 4)) != nil {
            frameExecutor.run { [self] in checkGap(onEvent: onEvent) }
        }
    }

    /// Runs on the executor.
    private func checkGap(onEvent: @Sendable (ReceiverEvent) -> Void) {
        guard hostPresent || awaitingFirstHost, let silence = sinceLastFrame?(), silence >= frameGap else { return }
        hostPresent = false
        awaitingFirstHost = false
        onEvent(.hostLost(.frameGap(frameGap)))
    }

    /// Starts a stopwatch on `clock`. Generic so the clock existential is opened
    /// and its `Instant` can live in the closure.
    static func stopwatch<C: Clock>(on clock: C) -> @Sendable () -> Duration where C.Duration == Duration {
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
