import Domain

/// The resolutions and frame rates the camera settings offer, worked out from the formats one camera supports.
/// The output is fixed at 1280x720 and 30 fps, so only 16:9 resolutions from 1280 to 1920 pixels wide are offered,
/// and only the frame rates the output can take (15, 24 and 30).
struct CameraOffers: Sendable {
    private let formats: [CameraFormat]

    init(formats: [CameraFormat]) {
        self.formats = formats
    }

    /// The offered resolutions that have at least one offered frame rate, without duplicates, by ascending width.
    var resolutions: [CameraResolution] {
        let candidates =
            formats
            .map { CameraResolution(width: $0.width, height: $0.height) }
            .filter { isOfferedShape($0) && !frameRates(at: $0).isEmpty }
        return Array(Set(candidates)).sorted { $0.width < $1.width }
    }

    /// The offered frame rates (15, 24, 30) that some format of this resolution supports, ascending.
    func frameRates(at resolution: CameraResolution) -> [Int] {
        offeredFrameRates.filter { framesPerSecond in
            formats(matching: resolution).contains { supports($0, framesPerSecond: framesPerSecond) }
        }
    }

    /// The choice of the format with the lowest `index` at this resolution that supports this frame rate, or nil when none does.
    func choice(at resolution: CameraResolution, framesPerSecond: Int) -> CameraFormatChoice? {
        formats(matching: resolution)
            .filter { supports($0, framesPerSecond: framesPerSecond) }
            .min { $0.index < $1.index }
            .map { CameraFormatChoice(index: $0.index, framesPerSecond: framesPerSecond) }
    }

    private func formats(matching resolution: CameraResolution) -> [CameraFormat] {
        formats.filter { $0.width == resolution.width && $0.height == resolution.height }
    }
}

private let offeredFrameRates = [15, 24, 30]

private func isOfferedShape(_ resolution: CameraResolution) -> Bool {
    resolution.width * 9 == resolution.height * 16 && (1280...1920).contains(resolution.width)
}

private func supports(_ format: CameraFormat, framesPerSecond: Int) -> Bool {
    format.minFramesPerSecond <= framesPerSecond && framesPerSecond <= format.maxFramesPerSecond
}
