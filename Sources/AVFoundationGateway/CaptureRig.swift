/// Implements the session wiring of `CaptureSessionGateway`.
/// Wraps `AVCaptureSession`, `AVCaptureDeviceInput` and `AVCaptureVideoDataOutput`.
/// One rig is one running session; stopping it tears the whole thing down.
import AVFoundation
import CoreVideo
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
        delegate = CaptureFrameDelegate(onFrame: onFrame)
        observers = CaptureEndObservers(session: session, onEnd: onEnd)
        let device = try AVCaptureDevice.default(for: .video).orThrow(CaptureSessionError.deviceUnavailable)
        let input = try Result { try AVCaptureDeviceInput(device: device) }
            .mapError { CaptureSessionError.configurationFailed("\($0)") }.get()
        try session.canAddInput(input).orThrow(CaptureSessionError.configurationFailed("cannot add input"))
        try session.canAddOutput(output).orThrow(CaptureSessionError.configurationFailed("cannot add output"))
        try session.canSetSessionPreset(.hd1280x720).orThrow(CaptureSessionError.configurationFailed("no 1280x720 preset"))
        session.sessionPreset = .hd1280x720
        session.addInput(input)
        session.addOutput(output)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: descriptor.width,
            kCVPixelBufferHeightKey as String: descriptor.height,
        ]
        output.setSampleBufferDelegate(delegate, queue: queue)
        session.startRunning()
    }

    func stop() {
        observers.removeAll()
        session.stopRunning()
    }
}
