import Metal

/// The one place the GPU suites ask whether a Metal device exists.
///
/// `.enabled(if: MetalDeviceProbe.isAvailable)` turns a machine without a
/// device into a skip instead of a failure; the CI `test-gpu` job then
/// asserts that nothing was skipped, so a runner that lost its device fails
/// loudly rather than passing an empty run (.claude/rules/gpu-testing.md).
///
/// Everything is computed on demand: an `MTLDevice` is not `Sendable`, so a
/// stored global would not compile under Swift 6, and the probe is cheap.
enum MetalDeviceProbe {
    /// The system default device, or `nil` when the process has no Metal access.
    static func makeDevice() -> (any MTLDevice)? {
        MTLCreateSystemDefaultDevice()
    }

    static var isAvailable: Bool {
        makeDevice() != nil
    }
}
