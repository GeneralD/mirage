/// Implements `CaptureSessionHandle` (the session wiring of `CaptureSessionGateway`).
/// Wraps `AVCaptureSession`, `AVCaptureDeviceInput` and `AVCaptureVideoDataOutput`.
/// One rig is one running session; stopping it tears the whole thing down.
import AVFoundation
import Domain

final class CaptureRig: @unchecked Sendable {
    let session = AVCaptureSession()
    let output = AVCaptureVideoDataOutput()
    private let delegate: CaptureFrameDelegate
    private let queue = DispatchQueue(label: "capture.frames")
    private let observers: CaptureEndObservers
    // Gives back the device lock that `configure` keeps for the whole run; called once, by `stop()`.
    private let release: () -> Void

    init(
        descriptor: SurfaceDescriptor,
        capture: CameraCapture,
        onFrame: @escaping @Sendable (CapturedSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws {
        let device = try CaptureRig.device(for: capture)
        let input = try Result { try AVCaptureDeviceInput(device: device) }
            .mapError { CaptureSessionError.configurationFailed("\($0)") }.get()
        delegate = CaptureFrameDelegate(onFrame: onFrame)
        observers = CaptureEndObservers(session: session, device: device, onEnd: onEnd)
        try session.canAddInput(input).orThrow(CaptureSessionError.configurationFailed("cannot add input"))
        try session.canAddOutput(output).orThrow(CaptureSessionError.configurationFailed("cannot add output"))
        session.addInput(input)
        session.addOutput(output)
        // Checked after the input is attached: the answer depends on the device the session holds.
        release = try CaptureRig.configure(device, for: capture.format, session: session)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = CaptureRig.videoSettings(for: descriptor)
        output.setSampleBufferDelegate(delegate, queue: queue)
        session.startRunning()
    }
}

extension CaptureRig: CaptureSessionHandle {
    func stop() {
        observers.removeAll()
        // Detach first so samples already queued never reach `onFrame` after stop.
        output.setSampleBufferDelegate(nil, queue: nil)
        session.stopRunning()
        release()
    }
}
