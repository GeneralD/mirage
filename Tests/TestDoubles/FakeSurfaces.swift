import Domain

/// An in-memory surface: identity, geometry and the last byte it was filled
/// with. Identity is the object itself (`===`), as with a real `IOSurface`.
public final class FakeSurfaceHandle: SurfaceHandle, Sendable {
    public let id: UInt32
    public let descriptor: SurfaceDescriptor
    private let fillByte = Locked<UInt8?>(nil)

    public init(id: UInt32, descriptor: SurfaceDescriptor = .hd720) {
        self.id = id
        self.descriptor = descriptor
    }

    public var backing: AnyObject { self }

    public var lastFill: UInt8? { fillByte.current }

    func fill(with byte: UInt8) {
        fillByte.set(byte)
    }
}

/// `IOSurfaceGateway` over `FakeSurfaceHandle`s. A send right is a name in a
/// table; `resolve` consumes it, so a right resolved twice fails like the
/// kernel would. Set `createError` to make allocation fail.
public final class FakeIOSurfaceGateway: IOSurfaceGateway, Sendable {
    private struct State {
        var nextID: UInt32 = 1
        var nextPortName: UInt32 = 0x1000
        var rights: [UInt32: FakeSurfaceHandle] = [:]
        var created: [FakeSurfaceHandle] = []
        var createError: SurfaceError?
    }

    private let state = Locked(State())

    public init() {}

    public var createdCount: Int { state.current.created.count }
    public var outstandingRights: Int { state.current.rights.count }

    public func failCreation(with error: SurfaceError?) {
        state.withLock { $0.createError = error }
    }

    public func create(_ descriptor: SurfaceDescriptor) throws -> any SurfaceHandle {
        try state.withLock { state in
            if let error = state.createError { throw error }
            let handle = FakeSurfaceHandle(id: state.nextID, descriptor: descriptor)
            state.nextID += 1
            state.created.append(handle)
            return handle
        }
    }

    public func makeSendRight(_ surface: any SurfaceHandle) throws -> MachSendRight {
        let fake = try (surface as? FakeSurfaceHandle).orThrow(SurfaceError.foreignHandle)
        return state.withLock { state in
            let name = state.nextPortName
            state.nextPortName += 1
            state.rights[name] = fake
            return MachSendRight(name: name)
        }
    }

    public func resolve(_ right: MachSendRight) throws -> any SurfaceHandle {
        try state.withLock { try $0.rights.removeValue(forKey: right.name).orThrow(SurfaceError.lookupFailed(portName: right.name)) }
    }

    public func identifier(_ surface: any SurfaceHandle) -> UInt32 {
        (surface as? FakeSurfaceHandle)?.id ?? 0
    }

    public func descriptor(_ surface: any SurfaceHandle) -> SurfaceDescriptor {
        (surface as? FakeSurfaceHandle)?.descriptor ?? .hd720
    }

    public func fill(_ surface: any SurfaceHandle, with byte: UInt8) throws {
        try (surface as? FakeSurfaceHandle).orThrow(SurfaceError.foreignHandle).fill(with: byte)
    }
}
