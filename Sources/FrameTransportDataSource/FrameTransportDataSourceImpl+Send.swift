import Domain

extension FrameTransportDataSourceImpl {
    /// Runs on the frame executor (the `FrameTransport` contract), so it may touch
    /// the confined port directly. A frame that cannot go is dropped with a reason;
    /// a live feed never waits and never retries one frame.
    public func send(_ surface: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) -> SendOutcome {
        // Not logged: it is the steady state before the extension is installed, at camera pace.
        guard let port = connection.value else {
            onEvent?(.frameDropped(.notConnected))
            return .dropped(.notConnected)
        }
        let right: MachSendRight
        do {
            right = try surfaces.makeSendRight(surface)
        } catch {
            return drop(code: -1, "no send right could be made for the surface: \(error)")
        }
        let message = FrameMessage(surface: right, descriptor: descriptor, presentationTime: presentationTime)
        do {
            try messaging.send(message, to: port)
            return .sent
        } catch MachError.destinationLost {
            return lose(port)
        } catch MachError.queueFull {
            // The extension is slower than the host: a steady-state drop at frame pace, so
            // not logged here; the link stays up and the observer tallies it per reason.
            onEvent?(.frameDropped(.queueFull))
            return .dropped(.queueFull)
        } catch MachError.sendFailed(let code) {
            return drop(code: code, "send refused")
        } catch {
            return drop(code: -1, "send failed: \(error)")
        }
    }

    /// Every drop also reaches the observer, which is where the owner's
    /// once-per-reason diagnostics live.
    private func drop(code: Int, _ reason: String) -> SendOutcome {
        errorLog.record(.transport, "frame dropped, \(reason) (code \(code))")
        onEvent?(.frameDropped(.sendFailed(code: code)))
        return .dropped(.sendFailed(code: code))
    }

    /// The extension's receive right is gone (it exited or was replaced): forget the
    /// stale port so the owner can `connect` again once a new instance registers.
    private func lose(_ lost: MachPortToken) -> SendOutcome {
        release()
        errorLog.record(.transport, "destination lost, port \(lost.name) released")
        onEvent?(.disconnected(.destinationLost))
        onEvent?(.frameDropped(.extensionUnavailable))
        return .dropped(.extensionUnavailable)
    }
}
