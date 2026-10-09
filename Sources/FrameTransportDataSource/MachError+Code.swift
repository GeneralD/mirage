import Domain

extension MachError {
    /// The raw kernel code the error carries, or -1 for the cases that carry none.
    /// Events report a code so the observer can log what the system said.
    var code: Int {
        switch self {
        case .bootstrapUnavailable(let code), .lookupFailed(let code), .checkInFailed(let code),
            .registerFailed(let code), .sendFailed(let code), .receiveFailed(let code):
            code
        case .destinationLost, .queueFull, .portDied, .malformedMessage:
            -1
        }
    }
}
