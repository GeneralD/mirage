import Dependencies
import Domain
import Foundation

/// The still image file as a `StillImage` (`StillImages`): the bytes come through `FileSystemGateway`,
/// the size and the pixels through `ImageIOGateway`, and every failure is answered as the
/// `StillImageProblem` it is, never thrown.
///
/// - **Reading.** The file is read at most `maxFileBytes + 1` bytes, so a larger one is never held whole.
///   Bytes over `maxFileBytes` are `.tooLarge` before anything is decoded. The size is read from the
///   header first: a side outside `1...maxSide` is `.dimensionsOutOfRange` before any pixel is decoded,
///   because a decoded image of that size would not fit the GPU surface the frame path makes from it.
/// - **Writing.** The image is encoded to PNG and written. The parent directory is not made.
public struct StillImageDataSourceImpl: StillImages, Sendable {
    @Dependency(\.fileSystemGateway) private var fileSystem
    @Dependency(\.imageIOGateway) private var imageIO

    private let maxFileBytes: Int
    private let maxSide: Int

    /// - Parameters:
    ///   - maxFileBytes: The most bytes a file may hold and still be read (64 MiB by default).
    ///   - maxSide: The most pixels a side may have (4096 by default: a 4096 × 4096 surface is 64 MiB).
    public init(maxFileBytes: Int = 64 * 1024 * 1024, maxSide: Int = 4096) {
        self.maxFileBytes = maxFileBytes
        self.maxSide = maxSide
    }
}

extension StillImageDataSourceImpl {
    public func read(_ path: String) async -> Result<StillImage, StillImageProblem> {
        let bytes: Data
        do {
            bytes = try fileSystem.readData(path, upTo: maxFileBytes + 1)
        } catch {
            return .failure(.unreadable(path: path))
        }
        guard bytes.count <= maxFileBytes else {
            return .failure(.tooLarge(limit: maxFileBytes))
        }
        let size: StillImageSize
        do {
            size = try imageIO.dimensions(of: bytes)
        } catch {
            return .failure(.notAnImage(path: path))
        }
        guard isWithinSides(size) else {
            return .failure(.dimensionsOutOfRange(width: size.width, height: size.height))
        }
        do {
            return .success(try imageIO.decode(bytes))
        } catch {
            return .failure(.notAnImage(path: path))
        }
    }

    public func write(_ image: StillImage, to path: String) async -> Result<Void, StillImageProblem> {
        do {
            let png = try imageIO.encodePNG(image)
            try fileSystem.writeData(png, to: path)
            return .success(())
        } catch {
            return .failure(.unwritable(path: path))
        }
    }

    /// Both sides are at least 1 and at most `maxSide`. Written as two comparisons: a closed range
    /// `1...maxSide` traps when `maxSide` is below 1.
    private func isWithinSides(_ size: StillImageSize) -> Bool {
        size.width >= 1 && size.width <= maxSide && size.height >= 1 && size.height <= maxSide
    }
}
