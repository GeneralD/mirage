/// Implements the session wiring of `CaptureSessionGateway`.
/// Wraps `AVCaptureSession`, `AVCaptureDeviceInput` and `AVCaptureVideoDataOutput`.
/// One rig is one running session; stopping it tears the whole thing down.
import AVFoundation
import Domain

final class CaptureRig: @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let delegate: CaptureFrameDelegate
    private let queue = DispatchQueue(label: "capture.frames")
    private let observers: CaptureEndObservers

    init(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (CapturedSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws {
        let device = try AVCaptureDevice.default(for: .video).orThrow(CaptureSessionError.deviceUnavailable)
        let input = try Result { try AVCaptureDeviceInput(device: device) }
            .mapError { CaptureSessionError.configurationFailed("\($0)") }.get()
        delegate = CaptureFrameDelegate(onFrame: onFrame)
        observers = CaptureEndObservers(session: session, device: device, onEnd: onEnd)
        try session.canAddInput(input).orThrow(CaptureSessionError.configurationFailed("cannot add input"))
        try session.canAddOutput(output).orThrow(CaptureSessionError.configurationFailed("cannot add output"))
        session.addInput(input)
        session.addOutput(output)
        // Checked after the input is attached: the answer depends on the device the session holds.
        try session.canSetSessionPreset(.hd1280x720).orThrow(CaptureSessionError.configurationFailed("no 1280x720 preset"))
        session.sessionPreset = .hd1280x720
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = CaptureRig.videoSettings(for: descriptor)
        output.setSampleBufferDelegate(delegate, queue: queue)
        session.startRunning()
    }

    func stop() {
        observers.removeAll()
        // Detach first so samples already queued never reach `onFrame` after stop.
        output.setSampleBufferDelegate(nil, queue: nil)
        session.stopRunning()
    }
}
