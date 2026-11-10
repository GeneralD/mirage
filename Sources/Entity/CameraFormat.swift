/// One capture format a camera supports: its frame size and the frame-rate range it can deliver.
public struct CameraFormat: Sendable, Hashable {
    /// The position in the owning camera's `formats` list. It has meaning only within that camera.
    public let index: Int
    public let width: Int
    public let height: Int
    public let minFramesPerSecond: Int
    public let maxFramesPerSecond: Int

    public init(index: Int, width: Int, height: Int, minFramesPerSecond: Int, maxFramesPerSecond: Int) {
        self.index = index
        self.width = width
        self.height = height
        self.minFramesPerSecond = minFramesPerSecond
        self.maxFramesPerSecond = maxFramesPerSecond
    }
}
