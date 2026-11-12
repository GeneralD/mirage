import Domain

/// Chooses the camera and the settings a capture uses, and what the settings screens show for them.
/// A running camera is used before a suspended one; among those, a remembered camera wins while it is connected, then a
/// physical camera before a virtual one, then the OS default camera, then the first in the list.
/// A remembered resolution or frame rate that the camera cannot give falls back to the M0 preset (1280x720 at 30 fps),
/// and then to the smallest resolution or the highest frame rate the camera offers.
struct CameraSelectionPolicy: Sendable {
    /// The camera to use, or nil when there is none. The ranking, most important first: running before suspended, so a
    /// remembered camera whose laptop lid is closed gives way to one that gives frames; the remembered camera; physical
    /// before virtual, so a virtual camera that is the OS default but whose app is not running is not picked on its own;
    /// the OS default camera; the order of the list.
    func device(among devices: [CameraDevice], selection: CameraSelection) -> CameraDevice? {
        devices.enumerated().min { rank($0.element, at: $0.offset, selection) < rank($1.element, at: $1.offset, selection) }?.element
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

    /// Where a camera stands in `device(among:selection:)`'s order: the lower, the sooner it is used.
    private func rank(_ camera: CameraDevice, at offset: Int, _ selection: CameraSelection) -> (Int, Int, Int, Int, Int) {
        (
            camera.isSuspended ? 1 : 0,
            camera.id == selection.deviceID ? 0 : 1,
            camera.isVirtual ? 1 : 0,
            camera.isSystemDefault ? 0 : 1,
            offset
        )
    }

    /// Whether the camera can be used: a remembered camera that is not connected is missing; otherwise the remembered
    /// camera, or the one in use when none was remembered, is suspended or available.
    private func availability(devices: [CameraDevice], selection: CameraSelection) -> CameraAvailability {
        guard let camera = device(among: devices, selection: selection) else { return .noCamera }
        guard let remembered = selection.deviceID else { return availability(of: camera) }
        guard let chosen = devices.first(where: { $0.id == remembered }) else {
            return .missing(selection.deviceName ?? remembered)
        }
        return availability(of: chosen)
    }

    private func availability(of camera: CameraDevice) -> CameraAvailability {
        camera.isSuspended ? .suspended(camera.name) : .available
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
