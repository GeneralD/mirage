import Dependencies
import Domain
import Foundation

/// What the user chose for the camera, kept in the user's defaults through `KeyValueStoreGateway`:
/// the device ID and its name as they are, the resolution as `<width>x<height>`, the frame rate as
/// an integer, and the mirroring as `1` or `0`. The keys and the forms are persisted, so they are
/// never renamed.
///
/// Reading never writes. A stored value that does not decode is left where it is (another build
/// may read it again): the setting reads as `nil`, and one developer-log line says it was ignored.
/// The mirroring reads as on only for `1`, so any other stored value reads as off.
public struct CameraPreferencesDataStoreImpl: Sendable {
    /// The defaults key the device ID lives under. Persisted, so never renamed.
    static let deviceIDKey = "cameraDeviceID"
    /// The defaults key the device name lives under. Persisted, so never renamed.
    static let deviceNameKey = "cameraDeviceName"
    /// The defaults key the resolution lives under. Persisted, so never renamed.
    static let resolutionKey = "cameraResolution"
    /// The defaults key the frame rate lives under. Persisted, so never renamed.
    static let frameRateKey = "cameraFrameRate"
    /// The defaults key the mirroring lives under. Persisted, so never renamed.
    static let mirroredKey = "cameraMirrored"

    @Dependency(\.keyValueStoreGateway) private var keyValueStore
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension CameraPreferencesDataStoreImpl: CameraPreferences {
    public func selection() -> CameraSelection {
        CameraSelection(
            deviceID: keyValueStore.string(forKey: Self.deviceIDKey),
            deviceName: keyValueStore.string(forKey: Self.deviceNameKey),
            resolution: storedResolution(),
            framesPerSecond: storedFrameRate(),
            isMirrored: keyValueStore.string(forKey: Self.mirroredKey) == "1"
        )
    }

    /// Every setting that is `nil` is removed; the mirroring is always written, as `1` or `0`.
    public func save(_ selection: CameraSelection) {
        store(selection.deviceID, forKey: Self.deviceIDKey)
        store(selection.deviceName, forKey: Self.deviceNameKey)
        store(selection.resolution.map { "\($0.width)x\($0.height)" }, forKey: Self.resolutionKey)
        store(selection.framesPerSecond.map { "\($0)" }, forKey: Self.frameRateKey)
        keyValueStore.set(selection.isMirrored ? "1" : "0", forKey: Self.mirroredKey)
    }

    private func storedResolution() -> CameraResolution? {
        guard let stored = keyValueStore.string(forKey: Self.resolutionKey) else { return nil }
        guard let resolution = Self.parseResolution(stored) else {
            developerLog.record(.camera, "stored camera resolution does not decode, ignored: \(stored)")
            return nil
        }
        return resolution
    }

    private func storedFrameRate() -> Int? {
        guard let stored = keyValueStore.string(forKey: Self.frameRateKey) else { return nil }
        guard let rate = Int(stored), (1...240).contains(rate) else {
            developerLog.record(.camera, "stored camera frame rate does not decode, ignored: \(stored)")
            return nil
        }
        return rate
    }

    private func store(_ value: String?, forKey key: String) {
        if let value {
            keyValueStore.set(value, forKey: key)
        } else {
            keyValueStore.removeValue(forKey: key)
        }
    }

    /// `<width>x<height>` with both sides an integer of at least 1. An empty side is not dropped, so
    /// `1280xx720` and `1280x720x30` are not a resolution.
    private static func parseResolution(_ stored: String) -> CameraResolution? {
        let parts = stored.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2,
            let width = Int(parts[0]), width >= 1,
            let height = Int(parts[1]), height >= 1
        else { return nil }
        return CameraResolution(width: width, height: height)
    }
}
