/// A 2-D count of threads or threadgroups.
public struct GridSize: Sendable, Hashable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// How a compute kernel is dispatched: whole threadgroups only
/// (`dispatchThreadgroups`, never `dispatchThreads`, which depends on the GPU
/// family), so the grid may overshoot the texture and every kernel bounds-checks
/// its own `gid`.
public struct DispatchGrid: Sendable, Hashable {
    public let threadgroups: GridSize
    public let threadsPerThreadgroup: GridSize

    public init(threadgroups: GridSize, threadsPerThreadgroup: GridSize) {
        self.threadgroups = threadgroups
        self.threadsPerThreadgroup = threadsPerThreadgroup
    }
}

extension DispatchGrid {
    /// Enough `side × side` threadgroups to cover `width × height` pixels
    /// (rounded up). 16 × 16 = 256 threads fits every `mac2` device.
    public static func covering(width: Int, height: Int, threadgroupSide side: Int = 16) -> DispatchGrid {
        DispatchGrid(
            threadgroups: GridSize(width: (width + side - 1) / side, height: (height + side - 1) / side),
            threadsPerThreadgroup: GridSize(width: side, height: side)
        )
    }

    /// The pixels the grid reaches; at least the size it was asked to cover.
    public var threads: GridSize {
        GridSize(width: threadgroups.width * threadsPerThreadgroup.width, height: threadgroups.height * threadsPerThreadgroup.height)
    }
}
