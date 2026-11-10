import Dependencies
import Domain
import Foundation
import StillImageDataSource
import TestDoubles
import Testing

@Suite("StillImageDataSource")
struct StillImageDataSourceTests {
    private static let path = "/works/still.png"
    private static let bytes = Data([1, 2, 3])
    /// A 2 × 2 image: 16 bytes, one row of 8 bytes per line.
    private static let photo = StillImage(width: 2, height: 2, bgra: [UInt8](repeating: 0x7F, count: 16))

    /// A subject over the given fakes, made the way the host makes it: its dependencies resolve when it is made.
    private static func subject(
        files: InMemoryFileSystemGateway, imageIO: FakeImageIOGateway, maxFileBytes: Int = 64 * 1024 * 1024, maxSide: Int = 4096
    ) -> StillImageDataSourceImpl {
        withDependencies {
            $0.fileSystemGateway = files
            $0.imageIOGateway = imageIO
        } operation: {
            StillImageDataSourceImpl(maxFileBytes: maxFileBytes, maxSide: maxSide)
        }
    }

    /// The problem a write answered with, `nil` when it succeeded.
    private static func problem(of result: Result<Void, StillImageProblem>) -> StillImageProblem? {
        if case .failure(let problem) = result { return problem }
        return nil
    }

    // MARK: Reading

    @Test("a file's bytes that the image decoder knows read as the scripted image, sized and decoded once, with at most the bound plus one byte read")
    func readsAnImage() async {
        let files = InMemoryFileSystemGateway()
        files.write(Self.path, bytes: Self.bytes)
        let imageIO = FakeImageIOGateway()
        imageIO.script(Self.photo, for: Self.bytes)
        let subject = Self.subject(files: files, imageIO: imageIO)

        let result = await subject.read(Self.path)

        #expect(result == .success(Self.photo))
        #expect(imageIO.dimensionRequests.values == [Self.bytes])
        #expect(imageIO.decodes.values == [Self.bytes])
        #expect(files.dataReads.values == [InMemoryFileSystemGateway.DataRead(path: Self.path, maxLength: 64 * 1024 * 1024 + 1)])
    }

    @Test("a missing file reads as unreadable at its path, and its size is never asked for")
    func missingFileIsUnreadable() async {
        let files = InMemoryFileSystemGateway()
        let imageIO = FakeImageIOGateway()
        let subject = Self.subject(files: files, imageIO: imageIO)

        let result = await subject.read(Self.path)

        #expect(result == .failure(.unreadable(path: Self.path)))
        #expect(imageIO.dimensionRequests.values.isEmpty)
    }

    @Test("a file the file system refuses to read reads as unreadable, and its size is never asked for")
    func refusedFileIsUnreadable() async {
        let files = InMemoryFileSystemGateway()
        files.write(Self.path, bytes: Self.bytes)
        files.failRead(of: Self.path, with: CocoaError(.fileReadNoPermission))
        let imageIO = FakeImageIOGateway()
        imageIO.script(Self.photo, for: Self.bytes)
        let subject = Self.subject(files: files, imageIO: imageIO)

        let result = await subject.read(Self.path)

        #expect(result == .failure(.unreadable(path: Self.path)))
        #expect(imageIO.dimensionRequests.values.isEmpty)
    }

    @Test("bytes over maxFileBytes read as tooLarge with the limit, and are neither sized nor decoded")
    func oversizedFileIsTooLarge() async {
        let files = InMemoryFileSystemGateway()
        let big = Data(repeating: 1, count: 9)
        files.write(Self.path, bytes: big)
        let imageIO = FakeImageIOGateway()
        imageIO.script(Self.photo, for: big)
        let subject = Self.subject(files: files, imageIO: imageIO, maxFileBytes: 8)

        let result = await subject.read(Self.path)

        #expect(result == .failure(.tooLarge(limit: 8)))
        #expect(files.dataReads.values == [InMemoryFileSystemGateway.DataRead(path: Self.path, maxLength: 9)])
        #expect(imageIO.dimensionRequests.values.isEmpty)
        #expect(imageIO.decodes.values.isEmpty)
    }

    @Test("a file of exactly maxFileBytes is read on, and decoded like any other")
    func fileAtTheLimitIsRead() async {
        let files = InMemoryFileSystemGateway()
        let exact = Data(repeating: 1, count: 8)
        files.write(Self.path, bytes: exact)
        let imageIO = FakeImageIOGateway()
        imageIO.script(Self.photo, for: exact)
        let subject = Self.subject(files: files, imageIO: imageIO, maxFileBytes: 8)

        let result = await subject.read(Self.path)

        #expect(result == .success(Self.photo))
    }

    @Test("bytes the image decoder does not know read as notAnImage at the path, and are not decoded")
    func unknownBytesAreNotAnImage() async {
        let files = InMemoryFileSystemGateway()
        files.write(Self.path, bytes: Self.bytes)
        let imageIO = FakeImageIOGateway()
        let subject = Self.subject(files: files, imageIO: imageIO)

        let result = await subject.read(Self.path)

        #expect(result == .failure(.notAnImage(path: Self.path)))
        #expect(imageIO.decodes.values.isEmpty)
    }

    @Test("bytes whose size can be read but whose pixels cannot be decoded read as notAnImage")
    func sizeWithoutPixelsIsNotAnImage() async {
        let files = InMemoryFileSystemGateway()
        files.write(Self.path, bytes: Self.bytes)
        let imageIO = FakeImageIOGateway()
        imageIO.script(StillImageSize(width: 3, height: 3), for: Self.bytes)
        let subject = Self.subject(files: files, imageIO: imageIO)

        let result = await subject.read(Self.path)

        #expect(result == .failure(.notAnImage(path: Self.path)))
        #expect(imageIO.decodes.values == [Self.bytes])
    }

    @Test("a side outside 1...maxSide reads as dimensionsOutOfRange with nothing decoded, and a side of exactly maxSide is read on")
    func sideOutOfRangeIsRefused() async {
        let files = InMemoryFileSystemGateway()
        let imageIO = FakeImageIOGateway()
        let wide = Data([1])
        let tall = Data([2])
        let flat = Data([3])
        let fits = Data([4])
        files.write("/works/wide.png", bytes: wide)
        files.write("/works/tall.png", bytes: tall)
        files.write("/works/flat.png", bytes: flat)
        files.write("/works/fits.png", bytes: fits)
        imageIO.script(StillImageSize(width: 5, height: 1), for: wide)
        imageIO.script(StillImageSize(width: 1, height: 5), for: tall)
        imageIO.script(StillImageSize(width: 4, height: 0), for: flat)
        let fourByOne = StillImage(width: 4, height: 1, bgra: [UInt8](repeating: 0x7F, count: 16))
        imageIO.script(fourByOne, for: fits)
        let subject = Self.subject(files: files, imageIO: imageIO, maxSide: 4)

        #expect(await subject.read("/works/wide.png") == .failure(.dimensionsOutOfRange(width: 5, height: 1)))
        #expect(await subject.read("/works/tall.png") == .failure(.dimensionsOutOfRange(width: 1, height: 5)))
        #expect(await subject.read("/works/flat.png") == .failure(.dimensionsOutOfRange(width: 4, height: 0)))
        #expect(await subject.read("/works/fits.png") == .success(fourByOne))
        #expect(imageIO.decodes.values == [fits])
    }

    @Test("the default bounds read a 4096-pixel side and refuse a 4097-pixel one")
    func defaultBoundsAreTheSpecifiedBounds() async {
        let files = InMemoryFileSystemGateway()
        let imageIO = FakeImageIOGateway()
        let edge = Data([1])
        let beyond = Data([2])
        let edgeImage = StillImage(width: 4096, height: 1, bgra: [UInt8](repeating: 0x7F, count: 4096 * 4))
        files.write("/works/edge.png", bytes: edge)
        files.write("/works/beyond.png", bytes: beyond)
        imageIO.script(edgeImage, for: edge)
        imageIO.script(StillImageSize(width: 4097, height: 1), for: beyond)
        let subject = withDependencies {
            $0.fileSystemGateway = files
            $0.imageIOGateway = imageIO
        } operation: {
            StillImageDataSourceImpl()
        }

        #expect(await subject.read("/works/edge.png") == .success(edgeImage))
        #expect(await subject.read("/works/beyond.png") == .failure(.dimensionsOutOfRange(width: 4097, height: 1)))
    }

    // MARK: Writing

    @Test("a written image is PNG bytes at the path, recorded once, and reads back as the same image")
    func writtenImageReadsBack() async {
        let files = InMemoryFileSystemGateway()
        files.makeDirectory("/works")
        let imageIO = FakeImageIOGateway()
        let subject = Self.subject(files: files, imageIO: imageIO)

        let written = await subject.write(Self.photo, to: Self.path)
        let read = await subject.read(Self.path)

        #expect(Self.problem(of: written) == nil)
        #expect(
            files.dataWrites.values
                == [InMemoryFileSystemGateway.DataWrite(path: Self.path, data: FakeImageIOGateway.encoded(Self.photo))])
        #expect(read == .success(Self.photo))
    }

    @Test("a write whose encoding fails is unwritable at its path, and writes no file")
    func failedEncodeWritesNothing() async {
        let files = InMemoryFileSystemGateway()
        files.makeDirectory("/works")
        let imageIO = FakeImageIOGateway()
        imageIO.failEncode(true)
        let subject = Self.subject(files: files, imageIO: imageIO)

        let written = await subject.write(Self.photo, to: Self.path)

        #expect(Self.problem(of: written) == .unwritable(path: Self.path))
        #expect(files.dataWrites.values.isEmpty)
    }

    @Test("a write into a directory that is not there is unwritable, and makes no directory")
    func missingParentIsUnwritable() async {
        let files = InMemoryFileSystemGateway()
        let imageIO = FakeImageIOGateway()
        let subject = Self.subject(files: files, imageIO: imageIO)

        let written = await subject.write(Self.photo, to: "/missing/still.png")

        #expect(Self.problem(of: written) == .unwritable(path: "/missing/still.png"))
        #expect(files.createdDirectories.values.isEmpty)
    }
}
