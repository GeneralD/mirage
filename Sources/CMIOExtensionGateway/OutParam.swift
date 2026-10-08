/// Support for `StreamOutputGatewayImpl` (port: `StreamOutputGateway`).
/// Wraps the C "out parameter" calling convention of CoreVideo without a `var`,
/// which the thin-live lint forbids; the status stays the caller's to check.
enum OutParam {
    static func call<Value>(_ body: (UnsafeMutablePointer<Value?>) -> Int32) -> (value: Value?, status: Int32) {
        let slot = UnsafeMutablePointer<Value?>.allocate(capacity: 1)
        slot.initialize(to: nil)
        defer {
            slot.deinitialize(count: 1)
            slot.deallocate()
        }
        let status = body(slot)
        return (slot.pointee, status)
    }
}
