import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

/// The host going away and coming back, end to end: both real processes' stacks over
/// `InMemoryFrameTransport`, every clock and executor stepped by hand. Each test is one
/// way the host disappears (`kill -9`, `kill -STOP`, app quit, extension exit) and what the
/// stream, the leases and the Mach rights look like on the far side.
@MainActor
@Suite("Host absence, end to end", .timeLimit(.minutes(1)))
struct HostAbsenceIntegrationTests {
    private let frameDuration = FrameRate.standard.frameDuration

    private func ns(_ base: UInt64, plus frames: Int) -> UInt64 {
        HostTimestamp(nanoseconds: base).advanced(by: frameDuration * frames).nanoseconds
    }

    // MARK: 1 Presence announcement

    @Test("starting the host announces a presence port and the extension watches it for a dead name")
    func hostStartAnnouncesPresence() async throws {
        let rig = LoopbackRig()
        let relay = await rig.startExtension()
        try await rig.startHost()
        #expect(await tickUntil(tick: { rig.ext.executor.drain() }, until: { rig.kernel.deadNameRequests.count >= 1 }))

        let presence = try #require(rig.kernel.presencePorts.values.first)
        let servicePort = try #require(rig.kernel.servicePort)
        #expect(rig.kernel.presencePorts.count == 1)
        #expect(rig.kernel.announced.count == 1)
        #expect(rig.kernel.announced.values.first?.right == presence.send)
        #expect(rig.kernel.announced.values.first?.port == servicePort)
        #expect(rig.kernel.deadNameRequests.count == 1)
        #expect(rig.kernel.deadNameRequests.values.first?.right == presence.send, "the extension watches the right the host announced")
        #expect(rig.kernel.deadNameRequests.values.first?.port == servicePort, "the notification comes back to the service port")

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    // MARK: 2 kill -9

    @Test("kill -9: the dead name puts the extension into slate, based after the last real frame")
    func killNineEntersSlate() async throws {
        let rig = LoopbackRig()
        let relay = await rig.startExtension()
        try await rig.startHost()
        rig.captureAndFlush(FakeSurfaceHandle(id: 1), at: 1_000_000_000)
        #expect(await rig.pumpExtension(untilReceived: 1))
        #expect(await tickUntil(tick: { rig.ext.executor.drain() }, until: { rig.kernel.deadNameRequests.count >= 1 }))
        // The extension's host-time reading is behind the last real frame: the base must not be.
        rig.ext.hostTime.set(.zero)

        rig.kernel.killHost()
        #expect(await tickUntil(tick: { rig.ext.executor.drain() }, until: { rig.ext.developer.contains("slate entered") }))

        #expect(rig.ext.developer.messages(in: .receiver).contains { $0.contains("hostLost") && $0.contains("deadName") })
        #expect(rig.ext.errors.contains("host lost"))
        #expect(rig.ext.scheduler.isRunning)
        let base = ns(1_000_000_000, plus: 1)
        #expect(rig.ext.developer.contains("slate entered base=\(base)"), "base = last real PTS + 1/fps, never behind it")

        rig.ext.scheduler.tick(times: 3)
        rig.ext.executor.drain()
        #expect(rig.streamedTimes == [1_000_000_000, base, ns(base, plus: 1), ns(base, plus: 2)])
        #expect(rig.ext.relay.stats.slateFrames == 3)
        #expect(rig.ext.relay.stats.summary.contains("slate=3"))

        try await rig.stopExtension(relay)
        rig.stopHost()
        #expect(rig.ext.pool.liveCount == 0, "the slate surface goes with the run")
        #expect(rig.host.pool.liveCount == 0)
    }

    // MARK: 3 kill -STOP / -CONT

    @Test("kill -STOP: the frame gap is noticed within gap + gap/4, slate runs, and the resumed host takes over monotonically")
    func stopAndContinue() async throws {
        let rig = LoopbackRig(frameGap: .seconds(2))
        let relay = await rig.startExtension()
        try await rig.startHost()
        rig.captureAndFlush(FakeSurfaceHandle(id: 1), at: 1_000_000_000)
        rig.captureAndFlush(FakeSurfaceHandle(id: 2), at: ns(1_000_000_000, plus: 1))
        #expect(await rig.pumpExtension(untilReceived: 2))
        rig.ext.hostTime.set(HostTimestamp(nanoseconds: 10_000_000_000))

        // The host is stopped, not dead: nothing arrives. The watchdog looks every gap/4.
        let step = Duration.milliseconds(500)
        let detectedAt = try await rig.advanceExtensionUntil(step: step, maxSteps: 5) { rig.ext.errors.contains("frameGap") }
        let steps = try #require(detectedAt)
        #expect(steps == 4, "silence reaches the gap on the fourth look, and no later than gap + gap/4")
        #expect(await tickUntil(tick: { rig.ext.executor.drain() }, until: { rig.ext.developer.contains("slate entered") }))
        #expect(rig.ext.developer.contains("slate entered base=10000000000"))

        rig.ext.scheduler.tick(times: 3)
        rig.ext.executor.drain()
        let lastSlate = ns(10_000_000_000, plus: 2)
        #expect(rig.streamedTimes.suffix(3) == [10_000_000_000, ns(10_000_000_000, plus: 1), lastSlate])
        #expect(rig.ext.relay.stats.summary.contains("slate=3"))

        // kill -CONT: the first frame the host sends is still stamped at capture time, behind the slate.
        let droppedBefore = rig.ext.relay.stats.framesDropped
        rig.captureAndFlush(FakeSurfaceHandle(id: 3), at: ns(10_000_000_000, plus: 1))
        #expect(await rig.pumpExtension(untilReceived: 3))
        #expect(rig.ext.relay.stats.framesDropped == droppedBefore + 1, "a real frame at or behind the last slate PTS is dropped once")
        #expect(rig.ext.scheduler.isRunning, "slate goes on until a newer real frame arrives")
        #expect(rig.streamedTimes.last == lastSlate)

        rig.captureAndFlush(FakeSurfaceHandle(id: 4), at: 11_000_000_000)
        #expect(await rig.pumpExtension(untilReceived: 4))
        #expect(rig.ext.scheduler.isRunning == false, "the first newer real frame ends slate")
        #expect(rig.ext.developer.contains("slate left"))
        #expect(rig.streamedTimes.last == 11_000_000_000)
        rig.captureAndFlush(FakeSurfaceHandle(id: 5), at: 12_000_000_000)
        #expect(await rig.pumpExtension(untilReceived: 5))

        let times = rig.streamedTimes
        #expect(times == times.sorted() && Set(times).count == times.count, "strictly increasing across the whole run")
        #expect(times.suffix(2) == [11_000_000_000, 12_000_000_000])

        try await rig.stopExtension(relay)
        rig.stopHost()
        #expect(rig.ext.pool.liveCount == 0)
        #expect(rig.host.pool.liveCount == 0)
    }

    // MARK: 4 App quit and relaunch

    @Test("app quit: the dropped presence puts the extension into slate; a relaunch replaces the old right once", arguments: [true, false])
    func explicitStopThenRestart(pumpBetween: Bool) async throws {
        let rig = LoopbackRig()
        let relay = await rig.startExtension()
        try await rig.startHost()
        rig.captureAndFlush(FakeSurfaceHandle(id: 1), at: 1_000_000_000)
        #expect(await rig.pumpExtension(untilReceived: 1))
        #expect(await tickUntil(tick: { rig.ext.executor.drain() }, until: { rig.kernel.deadNameRequests.count >= 1 }))
        let oldPresence = try #require(rig.kernel.presencePorts.values.first)

        rig.stopHost()
        #expect(rig.kernel.destroyed.values.filter { $0 == oldPresence.receive }.count == 1, "the host destroys its presence right on quit")
        if pumpBetween {
            #expect(await tickUntil(tick: { rig.ext.executor.drain() }, until: { rig.ext.developer.contains("slate entered") }))
            #expect(rig.ext.developer.messages(in: .receiver).contains { $0.contains("deadName") })
            rig.ext.scheduler.tick()
            rig.ext.executor.drain()
        }

        try await rig.startHost()
        #expect(await tickUntil(tick: { rig.ext.executor.drain() }, until: { rig.kernel.deadNameRequests.count >= 2 }))
        #expect(rig.kernel.presencePorts.count == 2)
        let newPresence = try #require(rig.kernel.presencePorts.values.last)
        #expect(newPresence != oldPresence)
        #expect(rig.kernel.deadNameRequests.values.last?.right == newPresence.send)
        #expect(
            rig.kernel.deallocated.values.filter { $0 == MachPortToken(name: oldPresence.send.name) }.count == 1,
            "the extension gives the old presence right back exactly once")

        rig.captureAndFlush(FakeSurfaceHandle(id: 2), at: 5_000_000_000)
        #expect(await rig.pumpExtension(untilReceived: 2))
        #expect(rig.streamedTimes.last == 5_000_000_000, "real frames resume")
        #expect(rig.ext.scheduler.isRunning == false)
        let times = rig.streamedTimes
        #expect(times == times.sorted() && Set(times).count == times.count)

        try await rig.stopExtension(relay)
        rig.stopHost()
        #expect(rig.kernel.destroyed.values.filter { $0 == newPresence.receive }.count == 1)
        #expect(rig.ext.pool.liveCount == 0)
        #expect(rig.host.pool.liveCount == 0)
    }

    // MARK: 5 Extension exit, host reconnect

    @Test("extension exit: the host reconnects on its own clock and the stream stays monotonic across the new instance")
    func extensionExitThenReconnect() async throws {
        let rig = LoopbackRig()
        let first = await rig.startExtension()
        try await rig.startHost()
        rig.captureAndFlush(FakeSurfaceHandle(id: 1), at: 1_000_000_000)
        #expect(await rig.pumpExtension(untilReceived: 1))
        #expect(await tickUntil(tick: { rig.ext.executor.drain() }, until: { rig.kernel.deadNameRequests.count >= 1 }))

        try await rig.stopExtension(first)
        // The next send learns the destination is gone.
        rig.captureAndFlush(FakeSurfaceHandle(id: 2), at: 2_000_000_000)
        #expect(rig.host.pipeline.phase == .reconnecting)
        #expect(rig.host.errors.contains("destinationLost"))
        // No extension is checked in: the look-ups fail on the retry policy's schedule.
        await rig.host.clock.advance(by: RetryPolicy.serviceLookup.delay(afterFailure: 1) ?? .zero)
        rig.host.executor.drain()
        #expect(rig.host.pipeline.phase == .reconnecting)
        let failedLookUps = rig.kernel.lookUps.count

        let second = await rig.startExtension()
        #expect(rig.kernel.checkIns.count == 2, "a new instance checks in under a new service port")
        let newService = try #require(rig.kernel.servicePort)
        var delays = 2
        while rig.host.pipeline.phase != .connected, delays < 12 {
            await rig.host.clock.advance(by: RetryPolicy.serviceLookup.delay(afterFailure: delays) ?? .zero)
            await tickUntil(
                tick: { rig.host.executor.drain() }, until: { rig.kernel.lookUps.count > failedLookUps || rig.host.pipeline.phase == .connected })
            delays += 1
        }
        #expect(await tickUntil(tick: { rig.host.executor.drain() }, until: { rig.host.pipeline.phase == .connected }))
        #expect(rig.host.pipeline.phase == .connected)

        rig.captureAndFlush(FakeSurfaceHandle(id: 3), at: 3_000_000_000)
        // Stats reset at the start of every run: 1 means the new instance received a frame.
        #expect(await rig.pumpExtension(untilReceived: 1))
        #expect(await tickUntil(tick: { rig.ext.executor.drain() }, until: { rig.kernel.deadNameRequests.count >= 2 }))
        #expect(rig.streamedTimes == [1_000_000_000, 3_000_000_000], "the frame reaches the new extension instance, PTS monotonic")
        #expect(rig.kernel.announced.values.last?.port == newService, "the new presence is announced to the new service port")

        try await rig.stopExtension(second)
        rig.stopHost()
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.ext.pool.liveCount == 0)
        for presence in rig.kernel.presencePorts.values {
            #expect(
                rig.kernel.destroyed.values.filter { $0 == presence.receive }.count == 1, "presence \(presence.receive.name) destroyed exactly once")
        }
        #expect(rig.kernel.presencePorts.count == 2)
    }

    // MARK: 6 Queue cap

    @Test("a full queue drops the frame as queueFull, keeps the link, and flows again once drained")
    func queueCap() async throws {
        let rig = LoopbackRig()
        // An extension that has checked in but whose receive loop is not running: nothing is
        // pumped, so every message stays queued (a waiting receiver would take them at once).
        let extensionBootstrap = rig.kernel.bootstrap(for: .extension)
        let extensionMessaging = rig.kernel.messaging(for: .extension)
        let service = try extensionBootstrap.checkIn(serviceName: ProductIdentity.machServiceName)
        try await rig.startHost()
        // The hello already holds one slot; fill the rest, then one more.
        let cap = rig.kernel.queueLimit
        for index in 1..<cap {
            rig.captureAndFlush(FakeSurfaceHandle(id: UInt32(index)), at: UInt64(index) * 1_000)
        }
        #expect(rig.host.pipeline.stats.framesSent == cap - 1)
        #expect(rig.host.pipeline.stats.framesDropped == 0)

        rig.captureAndFlush(FakeSurfaceHandle(id: 100), at: 100_000)
        #expect(rig.host.pipeline.stats.framesDropped == 1)
        #expect(rig.host.developer.contains("queueFull"), "the drop is reported as queueFull")
        #expect(rig.host.pipeline.phase == .connected, "a full queue is not a lost destination")
        #expect(rig.host.errors.contains("disconnected") == false)
        #expect(rig.kernel.lookUps.count == 1, "the link was kept, not re-established")

        // Pump: take everything the extension would have read.
        var drained: [IncomingMessage] = []
        for _ in 0..<cap { drained.append(try await extensionMessaging.receive(on: service)) }
        let framePTS = drained.compactMap { message -> UInt64? in
            guard case .frame(let frame) = message else { return nil }
            return frame.presentationTime.nanoseconds
        }
        #expect(framePTS == (1..<cap).map { UInt64($0) * 1_000 }, "the dropped frame never made it, the queued ones are in order")

        rig.captureAndFlush(FakeSurfaceHandle(id: 101), at: 101_000)
        let next = try await extensionMessaging.receive(on: service)
        guard case .frame(let frame) = next else {
            Issue.record("expected a frame, got \(next)")
            return
        }
        #expect(frame.presentationTime.nanoseconds == 101_000, "after the pump a new frame flows over the same link")
        #expect(rig.kernel.lookUps.count == 1)
        rig.stopHost()
        #expect(rig.host.pool.liveCount == 0)
    }

    // MARK: 7 Lease balance property

    @Test("any interleaving of host and extension events keeps leases balanced and the stream strictly increasing", arguments: Seeds.range(0..<50))
    func leaseBalanceProperty(seed: UInt64) async throws {
        var generator = SeededGenerator(seed: seed)
        let rig = LoopbackRig()
        let relay = await rig.startExtension()
        try await rig.startHost()
        var hostUp = true
        var pts: UInt64 = 1_000_000_000
        var nextID: UInt32 = 1_000_000
        var minted: [FakeSurfaceHandle] = []

        for _ in 0..<60 {
            switch Int.random(in: 0..<10, using: &generator) {
            case 0, 1, 2:
                guard hostUp else { break }
                // Mostly forward; now and then a capture clock that steps back.
                let back = Int.random(in: 0..<8, using: &generator) == 0
                pts = back ? max(1, pts - 40_000_000) : pts + UInt64.random(in: 1...60_000_000, using: &generator)
                let handle = FakeSurfaceHandle(id: nextID)
                nextID += 1
                minted.append(handle)
                rig.captureAndFlush(handle, at: pts)
            case 3:
                rig.ext.executor.drain()
            case 4:
                rig.ext.scheduler.tick()
                rig.ext.executor.drain()
            case 5:
                await rig.ext.clock.advance(by: .milliseconds(Int.random(in: 1...3) * 250))
                rig.ext.executor.drain()
            case 6:
                guard hostUp else { break }
                hostUp = false
                rig.kernel.killHost()
                rig.stopHost()
            case 7:
                if hostUp { rig.stopHost() }
                hostUp = false
            case 8:
                guard !hostUp else { break }
                try await rig.startHost()
                hostUp = true
            default:
                rig.ext.stream.emit(Bool.random(using: &generator) ? .streamStarted : .streamStopped)
                rig.ext.hostTime.set(HostTimestamp(nanoseconds: pts + UInt64.random(in: 0...200_000_000, using: &generator)))
            }
            for _ in 0..<3 {
                rig.ext.executor.drain()
                rig.host.executor.drain()
                await Task.yield()
            }
        }

        rig.ext.executor.drain()
        if hostUp { rig.stopHost() }
        try await rig.stopExtension(relay)
        rig.stopHost()

        #expect(rig.host.pool.liveCount == 0, "seed \(seed): host leases balanced")
        #expect(rig.ext.pool.liveCount == 0, "seed \(seed): extension leases balanced")
        let times = rig.streamedTimes
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 }, "seed \(seed): stream PTS strictly increasing, got \(times)")
        for sent in rig.ext.stream.sent.values {
            let handle = sent.surface as? FakeSurfaceHandle
            let fromHost = minted.contains { $0 === handle }
            let slate = handle?.lastFill == 0 && !(handle.map { $0.id >= 1_000_000 } ?? false)
            #expect(fromHost || slate, "seed \(seed): the stream only sees a host surface (same identity) or an extension slate surface")
        }
    }
}

extension LoopbackRig {
    /// One camera frame into the host's slot, one scheduler tick to send it, then the host executor.
    func captureAndFlush(_ handle: FakeSurfaceHandle, at nanoseconds: UInt64) {
        capture(handle, at: nanoseconds)
        host.executor.drain()
    }

    /// Moves the extension's clock by `step` at a time, draining its executor after each
    /// step, until `condition` holds. Returns the number of steps taken, or `nil` when it
    /// did not hold within `maxSteps`. The clock is the only thing that moves.
    @MainActor
    func advanceExtensionUntil(step: Duration, maxSteps: Int, _ condition: () -> Bool) async throws -> Int? {
        for taken in 1...maxSteps {
            await ext.clock.advance(by: step)
            #expect(await tickUntil(tick: { ext.executor.drain() }, until: { ext.executor.pendingCount == 0 }))
            for _ in 0..<5 {
                ext.executor.drain()
                await Task.yield()
            }
            if condition() { return taken }
        }
        return nil
    }
}
