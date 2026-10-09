import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("InMemoryFrameTransport", .timeLimit(.minutes(1)))
struct InMemoryFrameTransportTests {
    private let service = "test.service"

    private func frame(_ nanoseconds: UInt64) -> FrameMessage {
        FrameMessage(surface: MachSendRight(name: 1), descriptor: .hd720, presentationTime: HostTimestamp(nanoseconds: nanoseconds))
    }

    @Test("look-up fails before check-in and names the checked-in port afterwards")
    func lookUpNeedsCheckIn() throws {
        let transport = InMemoryFrameTransport()
        #expect(throws: MachError.lookupFailed(code: 1102)) { try transport.bootstrap(for: .host).lookUp(serviceName: service) }

        let port = try transport.bootstrap(for: .extension).checkIn(serviceName: service)

        #expect(try transport.bootstrap(for: .host).lookUp(serviceName: service) == port)
        #expect(transport.servicePort == port)
        #expect(transport.checkIns.values == [service])
        #expect(transport.lookUps.count == 2)
    }

    @Test("a second check-in registers a fresh port and look-up follows it")
    func freshPortPerCheckIn() throws {
        let transport = InMemoryFrameTransport()
        let first = try transport.bootstrap(for: .extension).checkIn(serviceName: service)
        let second = try transport.bootstrap(for: .extension).checkIn(serviceName: service)

        #expect(first != second)
        #expect(try transport.bootstrap(for: .host).lookUp(serviceName: service) == second)
    }

    @Test("failNextLookUps fails that many look-ups with the given code, then the table answers")
    func scriptedLookUpFailures() throws {
        let transport = InMemoryFrameTransport()
        let port = try transport.bootstrap(for: .extension).checkIn(serviceName: service)
        transport.failNextLookUps(2, code: 5)
        let host = transport.bootstrap(for: .host)

        #expect(throws: MachError.lookupFailed(code: 5)) { try host.lookUp(serviceName: service) }
        #expect(throws: MachError.lookupFailed(code: 5)) { try host.lookUp(serviceName: service) }
        #expect(try host.lookUp(serviceName: service) == port)
    }

    @Test("frames arrive in order, and a receive that was waiting gets the next send")
    func fifoAndWaiter() async throws {
        let transport = InMemoryFrameTransport()
        let port = try transport.bootstrap(for: .extension).checkIn(serviceName: service)
        let messaging = transport.messaging(for: .host)

        try messaging.send(frame(1), to: port)
        try messaging.send(frame(2), to: port)
        #expect(try await messaging.receive(on: port) == .frame(frame(1)))
        #expect(try await messaging.receive(on: port) == .frame(frame(2)))

        let waiting = Task { try await messaging.receive(on: port) }
        await transport.receiveCalls.waitForCount(3)
        try messaging.send(frame(3), to: port)
        #expect(try await waiting.value == .frame(frame(3)))
    }

    @Test("the queue cap is five by default: the sixth queued frame is queueFull, and receiving frees a slot")
    func queueCap() async throws {
        let transport = InMemoryFrameTransport()
        let port = try transport.bootstrap(for: .extension).checkIn(serviceName: service)
        let messaging = transport.messaging(for: .host)
        for stamp in 1...5 { try messaging.send(frame(UInt64(stamp)), to: port) }

        #expect(throws: MachError.queueFull) { try messaging.send(frame(6), to: port) }
        _ = try await messaging.receive(on: port)

        try messaging.send(frame(7), to: port)
    }

    @Test("the queue limit is configurable")
    func customCap() throws {
        let transport = InMemoryFrameTransport(queueLimit: 1)
        let port = try transport.bootstrap(for: .extension).checkIn(serviceName: service)
        let messaging = transport.messaging(for: .host)

        try messaging.send(frame(1), to: port)

        #expect(throws: MachError.queueFull) { try messaging.send(frame(2), to: port) }
    }

    @Test("destroying the receive right fails sends, ends a pending receive and removes the service")
    func destroy() async throws {
        let transport = InMemoryFrameTransport()
        let bootstrap = transport.bootstrap(for: .extension)
        let messaging = transport.messaging(for: .host)
        let port = try bootstrap.checkIn(serviceName: service)
        let pending = Task { try await messaging.receive(on: port) }
        await transport.receiveCalls.waitForCount(1)

        bootstrap.destroyReceiveRight(port)

        await #expect(throws: MachError.portDied) { try await pending.value }
        #expect(throws: MachError.destinationLost) { try messaging.send(frame(1), to: port) }
        #expect(throws: MachError.lookupFailed(code: 1102)) { try transport.bootstrap(for: .host).lookUp(serviceName: service) }
        await #expect(throws: MachError.portDied) { try await messaging.receive(on: port) }
        #expect(transport.destroyed.values == [port])
        #expect(transport.servicePort == nil)
    }

    @Test("a hello reaches the extension, and a presence port's death is announced to the registered port")
    func deadNameDelivery() async throws {
        let transport = InMemoryFrameTransport()
        let servicePort = try transport.bootstrap(for: .extension).checkIn(serviceName: service)
        let host = transport.bootstrap(for: .host)
        let presence = try host.makePresencePort()
        try transport.messaging(for: .host).announce(presence.send, to: servicePort)
        let extensionMessaging = transport.messaging(for: .extension)
        #expect(try await extensionMessaging.receive(on: servicePort) == .hello(presence.send))
        try transport.bootstrap(for: .extension).requestDeadNameNotification(of: presence.send, to: servicePort)

        host.destroyReceiveRight(presence.receive)

        #expect(try await extensionMessaging.receive(on: servicePort) == .deadName(presence.receive))
        #expect(transport.announced.count == 1)
        #expect(transport.presencePorts.values == [presence])
        #expect(transport.deadNameRequests.count == 1)
    }

    @Test("the dead-name notification is not held back by a full queue")
    func deadNameBypassesTheCap() async throws {
        let transport = InMemoryFrameTransport(queueLimit: 1)
        let servicePort = try transport.bootstrap(for: .extension).checkIn(serviceName: service)
        let host = transport.bootstrap(for: .host)
        let presence = try host.makePresencePort()
        try transport.bootstrap(for: .extension).requestDeadNameNotification(of: presence.send, to: servicePort)
        try transport.messaging(for: .host).send(frame(1), to: servicePort)

        host.destroyReceiveRight(presence.receive)

        let messaging = transport.messaging(for: .extension)
        #expect(try await messaging.receive(on: servicePort) == .frame(frame(1)))
        #expect(try await messaging.receive(on: servicePort) == .deadName(presence.receive))
    }

    @Test("asking for a notification on a port that is already dead delivers it at once")
    func alreadyDead() async throws {
        let transport = InMemoryFrameTransport()
        let servicePort = try transport.bootstrap(for: .extension).checkIn(serviceName: service)
        let host = transport.bootstrap(for: .host)
        let presence = try host.makePresencePort()
        host.destroyReceiveRight(presence.receive)

        try transport.bootstrap(for: .extension).requestDeadNameNotification(of: presence.send, to: servicePort)

        #expect(try await transport.messaging(for: .extension).receive(on: servicePort) == .deadName(presence.receive))
    }

    @Test("a notification for a right nobody knows is refused")
    func unknownRight() throws {
        let transport = InMemoryFrameTransport()
        let servicePort = try transport.bootstrap(for: .extension).checkIn(serviceName: service)

        #expect(throws: MachError.registerFailed(code: 15)) {
            try transport.bootstrap(for: .extension).requestDeadNameNotification(of: MachSendRight(name: 0xFFFF), to: servicePort)
        }
    }

    @Test("killHost destroys every host presence port without host-side cleanup, and spares the extension's own rights")
    func killHost() async throws {
        let transport = InMemoryFrameTransport()
        let extensionBootstrap = transport.bootstrap(for: .extension)
        let servicePort = try extensionBootstrap.checkIn(serviceName: service)
        let host = transport.bootstrap(for: .host)
        let first = try host.makePresencePort()
        let second = try host.makePresencePort()
        try extensionBootstrap.requestDeadNameNotification(of: first.send, to: servicePort)
        try extensionBootstrap.requestDeadNameNotification(of: second.send, to: servicePort)

        transport.killHost()

        let messaging = transport.messaging(for: .extension)
        let notified = Set([try await messaging.receive(on: servicePort), try await messaging.receive(on: servicePort)])
        #expect(notified == [.deadName(first.receive), .deadName(second.receive)])
        #expect(transport.destroyed.values.isEmpty, "the host did not clean up after itself")
        #expect(transport.servicePort == servicePort, "the extension's service port survives the host")
    }

    @Test("an extension-side presence port is not host-held, so killHost leaves it alone")
    func extensionPortsSurviveKillHost() throws {
        let transport = InMemoryFrameTransport()
        let servicePort = try transport.bootstrap(for: .extension).checkIn(serviceName: service)
        let presence = try transport.bootstrap(for: .extension).makePresencePort()
        try transport.bootstrap(for: .extension).requestDeadNameNotification(of: presence.send, to: servicePort)

        transport.killHost()

        try transport.messaging(for: .host).send(frame(1), to: presence.receive)
    }
}
