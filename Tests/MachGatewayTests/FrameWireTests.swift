import Darwin
import Domain
import TestSupport
import Testing

@testable import MachGateway

@Suite("Frame wire codec")
struct FrameWireTests {
    private let destination = MachPortToken(name: 0x1234)

    private func randomMessage(_ generator: inout SeededGenerator) -> FrameMessage {
        FrameMessage(
            surface: MachSendRight(name: UInt32.random(in: 1...UInt32.max, using: &generator)),
            descriptor: SurfaceDescriptor(
                width: Int.random(in: 0...Int(UInt32.max), using: &generator),
                height: Int.random(in: 0...Int(UInt32.max), using: &generator),
                pixelFormat: .bgra32,
                bytesPerRow: Int.random(in: 0...Int(UInt32.max), using: &generator)),
            presentationTime: HostTimestamp(nanoseconds: UInt64.random(in: 0...UInt64.max, using: &generator)))
    }

    private var valid: FrameWire {
        FrameWire(
            FrameMessage(surface: MachSendRight(name: 7), descriptor: .hd720, presentationTime: HostTimestamp(nanoseconds: 99)),
            to: destination)
    }

    @Test("encoding then decoding returns the same message", arguments: standardSeeds)
    func roundTrip(seed: UInt64) throws {
        var generator = SeededGenerator(seed: seed)
        let message = randomMessage(&generator)

        #expect(try FrameWire(message, to: destination).message() == message)
    }

    @Test("the encoded header addresses the destination, copies its right, moves the surface right and is complex")
    func header() {
        let wire = valid

        #expect(wire.header.msgh_remote_port == destination.name)
        #expect(wire.header.msgh_id == 0x10001)
        #expect(wire.header.msgh_size == FrameWire.size)
        #expect(wire.header.msgh_bits & MACH_MSGH_BITS_COMPLEX != 0)
        #expect(wire.header.msgh_bits & 0xFF == mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND))
        #expect(wire.body.msgh_descriptor_count == 1)
        #expect(wire.port.disposition == mach_msg_type_name_t(MACH_MSG_TYPE_MOVE_SEND))
    }

    @Test("the wire is the fixed 64-byte layout the extension reads")
    func layout() {
        #expect(MemoryLayout<FrameWire>.size == 64)
        #expect(MemoryLayout<FrameWire>.offset(of: \.payload) == 40)
        #expect(MemoryLayout<FramePayload>.size == 24)
    }

    @Test("a send right reported as PORT_SEND by the kernel decodes the same")
    func receivedDisposition() throws {
        let wire = valid
        let received = mach_msg_port_descriptor_t(
            name: wire.port.name, pad1: 0, pad2: 0, disposition: mach_msg_type_name_t(MACH_MSG_TYPE_PORT_SEND), type: wire.port.type)

        #expect(try wire.replacing(port: received).message() == wire.message())
    }

    @Test("a carried right is reported only for a well-shaped complex message with a port descriptor")
    func carriedRight() {
        let wire = valid
        let simple = wire.header.replacing(bits: wire.header.msgh_bits & ~MACH_MSGH_BITS_COMPLEX)
        let short = wire.header.replacing(size: 24)
        let outOfLine = mach_msg_port_descriptor_t(
            name: 7, pad1: 0, pad2: 0, disposition: wire.port.disposition, type: mach_msg_descriptor_type_t(MACH_MSG_OOL_DESCRIPTOR))

        #expect(wire.carriedRight() == CarriedRight(name: 7, disposition: mach_msg_type_name_t(MACH_MSG_TYPE_MOVE_SEND)))
        #expect(wire.replacing(port: outOfLine).carriedRight() == nil)
        #expect(wire.replacing(header: simple).carriedRight() == nil)
        #expect(wire.replacing(header: short).carriedRight() == nil)
        #expect(wire.replacing(body: mach_msg_body_t(msgh_descriptor_count: 2)).carriedRight() == nil)
    }

    @Test("only a receive disposition is released as a receive right")
    func receiveKind() {
        let send = CarriedRight(name: 7, disposition: mach_msg_type_name_t(MACH_MSG_TYPE_PORT_SEND))
        let once = CarriedRight(name: 7, disposition: mach_msg_type_name_t(MACH_MSG_TYPE_PORT_SEND_ONCE))
        let receive = CarriedRight(name: 7, disposition: mach_msg_type_name_t(MACH_MSG_TYPE_PORT_RECEIVE))

        #expect([send.isReceive(), once.isReceive(), receive.isReceive()] == [false, false, true])
    }

    @Test("every deviation from the frame shape is malformedMessage")
    func malformed() {
        let wire = valid
        let notPort = mach_msg_port_descriptor_t(
            name: 7, pad1: 0, pad2: 0, disposition: wire.port.disposition, type: mach_msg_descriptor_type_t(MACH_MSG_OOL_DESCRIPTOR))
        let receiveRight = mach_msg_port_descriptor_t(
            name: 7, pad1: 0, pad2: 0, disposition: mach_msg_type_name_t(MACH_MSG_TYPE_MOVE_RECEIVE), type: wire.port.type)
        let deviations: [FrameWire] = [
            wire.replacing(header: wire.header.replacing(id: 0x10002)),
            wire.replacing(header: wire.header.replacing(size: FrameWire.size + 4)),
            wire.replacing(header: wire.header.replacing(bits: wire.header.msgh_bits & ~MACH_MSGH_BITS_COMPLEX)),
            wire.replacing(body: mach_msg_body_t(msgh_descriptor_count: 0)),
            wire.replacing(port: notPort),
            wire.replacing(port: receiveRight),
            wire.replacing(payload: wire.payload.replacing(fourCC: 0)),
        ]

        for deviation in deviations {
            #expect(throws: MachError.malformedMessage) { try deviation.message() }
        }
    }
}
