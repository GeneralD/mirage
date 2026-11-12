import Dependencies
import Domain

/// Works out the camera state from the stored choice and the attached cameras, and hands the capture to the
/// camera source. `refresh()` reads the choice and never saves it; each command saves one item of it when the
/// state offers the new value.
public struct CameraSelectionUseCaseImpl: Sendable {
    @Dependency(\.cameraSelectionRepository) private var cameraSelectionRepository
    @Dependency(\.developerLog) private var developerLog

    private let policy = CameraSelectionPolicy()

    public init() {}
}

extension CameraSelectionUseCaseImpl: CameraSelectionUseCase {
    public func refresh() -> CameraState {
        let state = resolved(cameraSelectionRepository.storedSelection())
        cameraSelectionRepository.setMirrored(state.isMirrored)
        switch state.availability {
        case .available:
            break
        case .missing(let name):
            developerLog.record(.camera, "camera not connected: \(name)")
        case .suspended(let name):
            developerLog.record(.camera, "camera suspended: \(name)")
        case .noCamera:
            developerLog.record(.camera, "no camera found")
        }
        return state
    }

    public func changes() -> AsyncStream<Void> {
        cameraSelectionRepository.changes()
    }

    public func selectDevice(_ id: String) -> CameraState {
        let selection = cameraSelectionRepository.storedSelection()
        let current = derived(selection).state
        guard let device = current.devices.first(where: { $0.id == id }) else { return current }
        return commit(replacing(selection, device: device))
    }

    public func selectResolution(_ resolution: CameraResolution) -> CameraState {
        let selection = cameraSelectionRepository.storedSelection()
        let current = derived(selection).state
        guard current.resolutions.contains(resolution) else { return current }
        return commit(replacing(selection, resolution: resolution))
    }

    public func selectFrameRate(_ framesPerSecond: Int) -> CameraState {
        let selection = cameraSelectionRepository.storedSelection()
        let current = derived(selection).state
        guard current.frameRates.contains(framesPerSecond) else { return current }
        return commit(replacing(selection, framesPerSecond: framesPerSecond))
    }

    public func setMirrored(_ isMirrored: Bool) -> CameraState {
        commit(replacing(cameraSelectionRepository.storedSelection(), isMirrored: isMirrored))
    }
}

extension CameraSelectionUseCaseImpl {
    /// The state for a selection, with the capture applied to the camera source when there is a camera to capture.
    private func resolved(_ selection: CameraSelection) -> CameraState {
        let (state, capture) = derived(selection)
        if let capture {
            cameraSelectionRepository.apply(capture)
        }
        return state
    }

    /// The state for a selection and the capture it asks for, worked out without touching the camera source.
    /// Only the chosen camera's formats are read, so the other cameras are not asked for theirs.
    private func derived(_ selection: CameraSelection) -> (state: CameraState, capture: CameraCapture?) {
        let devices = cameraSelectionRepository.devices()
        let camera = policy.device(among: devices, selection: selection)
        let formats = camera.map { cameraSelectionRepository.formats(ofDevice: $0.id) } ?? []
        return (
            policy.state(devices: devices, formats: formats, selection: selection),
            policy.capture(devices: devices, formats: formats, selection: selection)
        )
    }

    /// Saves an accepted choice, then reflects it the way `refresh()` does and returns the new state.
    private func commit(_ selection: CameraSelection) -> CameraState {
        cameraSelectionRepository.save(selection)
        let state = resolved(selection)
        cameraSelectionRepository.setMirrored(state.isMirrored)
        return state
    }

    /// The stored choice with one item replaced; every other item keeps its stored value.
    private func replacing(
        _ selection: CameraSelection,
        device: CameraDevice? = nil,
        resolution: CameraResolution? = nil,
        framesPerSecond: Int? = nil,
        isMirrored: Bool? = nil
    ) -> CameraSelection {
        CameraSelection(
            deviceID: device?.id ?? selection.deviceID,
            deviceName: device?.name ?? selection.deviceName,
            resolution: resolution ?? selection.resolution,
            framesPerSecond: framesPerSecond ?? selection.framesPerSecond,
            isMirrored: isMirrored ?? selection.isMirrored)
    }
}
