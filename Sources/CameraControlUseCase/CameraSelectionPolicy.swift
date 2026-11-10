import Domain

/// Chooses the camera and the settings a capture uses, and what the settings screens show for them.
/// A remembered camera wins while it is connected; otherwise the OS default camera is used, then the first camera.
/// A remembered resolution or frame rate that the camera cannot give falls back to the M0 preset (1280x720 at 30 fps),
/// and then to the smallest resolution or the highest frame rate the camera offers.
struct CameraSelectionPolicy: Sendable {
    /// The camera to use: the remembered one when it is connected, else the OS default camera, else the first camera,
    /// or nil when there is none.
    func device(among devices: [CameraDevice], selection: CameraSelection) -> CameraDevice? {
        devices.first { $0.id == selection.deviceID }
            ?? devices.first { $0.isSystemDefault }
            ?? devices.first
    }

    /// What the settings screens read: the cameras, the choices on offer, the current choice, and whether it can be used.
    func state(devices: [CameraDevice], formats: [CameraFormat], selection: CameraSelection) -> CameraState {
        let chosen = resolved(devices: devices, formats: formats, selection: selection)
        return CameraState(
            devices: devices,
            selectedDeviceID: chosen.device?.id,
            availability: availability(devices: devices, selection: selection),
            resolutions: chosen.offers.resolutions,
            selectedResolution: chosen.resolution,
            frameRates: chosen.frameRates,
            selectedFrameRate: chosen.framesPerSecond,
            isMirrored: selection.isMirrored
        )
    }

    /// What a capture asks for: the camera, and the format at the chosen resolution and frame rate.
    /// The format is nil when no resolution or frame rate is chosen, which leaves the capture on the M0 preset.
    func capture(devices: [CameraDevice], formats: [CameraFormat], selection: CameraSelection) -> CameraCapture? {
        let chosen = resolved(devices: devices, formats: formats, selection: selection)
        guard let device = chosen.device else { return nil }
        guard let resolution = chosen.resolution, let framesPerSecond = chosen.framesPerSecond else {
            return CameraCapture(deviceID: device.id, format: nil)
        }
        return CameraCapture(
            deviceID: device.id,
            format: chosen.offers.choice(at: resolution, framesPerSecond: framesPerSecond)
        )
    }

    /// The camera, the offers and the choices that `state` and `capture` both read, worked out once so the two cannot disagree.
    private func resolved(devices: [CameraDevice], formats: [CameraFormat], selection: CameraSelection) -> Resolved {
        let camera = device(among: devices, selection: selection)
        // Without a camera there is nothing to offer, so the formats are not used.
        let offers = CameraOffers(formats: camera == nil ? [] : formats)
        let resolutions = offers.resolutions
        let resolution =
            resolutions.first { $0 == selection.resolution }
            ?? resolutions.first { $0 == m0Resolution }
            ?? resolutions.first
        let frameRates = resolution.map { offers.frameRates(at: $0) } ?? []
        let framesPerSecond =
            frameRates.first { $0 == selection.framesPerSecond }
            ?? frameRates.first { $0 == m0FramesPerSecond }
            ?? frameRates.max()
        return Resolved(
            device: camera,
            offers: offers,
            resolution: resolution,
            frameRates: frameRates,
            framesPerSecond: framesPerSecond
        )
    }

    private func availability(devices: [CameraDevice], selection: CameraSelection) -> CameraAvailability {
        guard !devices.isEmpty else { return .noCamera }
        guard let remembered = selection.deviceID else { return .available }
        guard devices.contains(where: { $0.id == remembered }) else {
            return .missing(selection.deviceName ?? remembered)
        }
        return .available
    }
}

private struct Resolved {
    let device: CameraDevice?
    let offers: CameraOffers
    let resolution: CameraResolution?
    let frameRates: [Int]
    let framesPerSecond: Int?
}

private let m0Resolution = CameraResolution(width: 1280, height: 720)
private let m0FramesPerSecond = 30
