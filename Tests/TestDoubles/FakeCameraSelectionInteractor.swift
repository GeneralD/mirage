import Combine
import Domain
import TestSupport

/// `CameraSelectionInteractor` as the Presenter suites see it: `state` is a `CurrentValueSubject`
/// the test drives with `publish(_:)`, so a subscriber gets the current state at once and every later
/// one. Commands are only recorded (`starts`, `stops`, `deviceSelections`, `resolutionSelections`,
/// `frameRateSelections`, `mirrorSettings`); nothing they would cause happens unless the test publishes it.
public final class FakeCameraSelectionInteractor: CameraSelectionInteractor, @unchecked Sendable {
    private let subject: CurrentValueSubject<CameraState, Never>
    /// One entry per `start()` call.
    public let starts = Collector<Void>()
    /// One entry per `stop()` call.
    public let stops = Collector<Void>()
    /// The ids `selectDevice` was called with, in call order.
    public let deviceSelections = Collector<String>()
    /// The resolutions `selectResolution` was called with, in call order.
    public let resolutionSelections = Collector<CameraResolution>()
    /// The frame rates `selectFrameRate` was called with, in call order.
    public let frameRateSelections = Collector<Int>()
    /// The flags `setMirrored` was called with, in call order.
    public let mirrorSettings = Collector<Bool>()

    public init(state: CameraState) {
        subject = CurrentValueSubject(state)
    }

    public var state: AnyPublisher<CameraState, Never> { subject.eraseToAnyPublisher() }

    /// Makes `state` the current state and sends it to every subscriber.
    public func publish(_ state: CameraState) {
        subject.send(state)
    }

    public func start() {
        starts.append(())
    }

    public func stop() {
        stops.append(())
    }

    public func selectDevice(_ id: String) {
        deviceSelections.append(id)
    }

    public func selectResolution(_ resolution: CameraResolution) {
        resolutionSelections.append(resolution)
    }

    public func selectFrameRate(_ framesPerSecond: Int) {
        frameRateSelections.append(framesPerSecond)
    }

    public func setMirrored(_ isMirrored: Bool) {
        mirrorSettings.append(isMirrored)
    }
}
