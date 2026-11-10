import Domain

// The wording and ids of the camera menu, as pure functions of `CameraState`, so that the
// camera menu's Presenter only moves them into its `@Published` values. The View draws them and
// decides nothing.

/// The camera menu's titles, rows and status line. A row's `id` is what the menu hands back
/// when the user picks it: a device id, a `<width>x<height>` resolution or a frame rate.
struct CameraMenuText: Sendable {
    let title = "Camera"
    let resolutionTitle = "Resolution"
    let frameRateTitle = "Frame Rate"
    let mirrorTitle = "Mirror"

    /// One row per camera the OS lists, in the state's order. The title is the camera's name.
    func devices(of state: CameraState) -> [CameraMenuOption] {
        state.devices.map { device in
            CameraMenuOption(id: device.id, title: device.name, isSelected: device.id == state.selectedDeviceID)
        }
    }

    /// One row per resolution on offer. The id is `1280x720`, the title `1280 × 720`.
    func resolutions(of state: CameraState) -> [CameraMenuOption] {
        state.resolutions.map { resolution in
            CameraMenuOption(
                id: "\(resolution.width)x\(resolution.height)",
                title: "\(resolution.width) \u{00D7} \(resolution.height)",
                isSelected: resolution == state.selectedResolution)
        }
    }

    /// One row per frame rate on offer. The id is `30`, the title `30 fps`.
    func frameRates(of state: CameraState) -> [CameraMenuOption] {
        state.frameRates.map { rate in
            CameraMenuOption(id: "\(rate)", title: "\(rate) fps", isSelected: rate == state.selectedFrameRate)
        }
    }

    /// Why the chosen camera cannot be used, or `nil` when it can.
    func status(of state: CameraState) -> String? {
        switch state.availability {
        case .available:
            return nil
        case .missing(let name):
            return "\(name) is not connected"
        case .noCamera:
            return "No camera found"
        }
    }

    /// The resolution an id names (`1920x1080`), or `nil` unless both sides are whole numbers of at least 1.
    func resolution(fromID id: String) -> CameraResolution? {
        let sides = id.split(separator: "x", omittingEmptySubsequences: false)
        guard sides.count == 2, let width = positive(sides[0]), let height = positive(sides[1]) else { return nil }
        return CameraResolution(width: width, height: height)
    }

    /// The frame rate an id names (`24`), or `nil` unless it is a whole number of at least 1.
    func frameRate(fromID id: String) -> Int? {
        positive(Substring(id))
    }

    private func positive(_ text: Substring) -> Int? {
        guard let value = Int(text), value >= 1 else { return nil }
        return value
    }
}
