import Dependencies
import Domain
import TestDoubles
import Testing

@testable import StillImageRepository

@Suite("StillImageRepository")
struct StillImageRepositoryTests {
    private static let photo = StillImage(width: 2, height: 2, bgra: [UInt8](repeating: 0x7F, count: 16))

    /// The problem a write answered with, `nil` when it succeeded.
    private static func problem(of result: Result<Void, StillImageProblem>) -> StillImageProblem? {
        if case .failure(let problem) = result { return problem }
        return nil
    }

    private func makeSubject(_ dataSource: FakeStillImages) -> StillImageRepositoryImpl {
        withDependencies {
            $0.stillImages = dataSource
        } operation: {
            StillImageRepositoryImpl()
        }
    }

    @Test("read answers the image the DataSource reads, and hands it the path once")
    func readAnswersTheDataSourceImage() async {
        let dataSource = FakeStillImages()
        dataSource.script(.success(Self.photo), for: "a.png")
        let subject = makeSubject(dataSource)

        let result = await subject.read("a.png")

        #expect(result == .success(Self.photo))
        #expect(dataSource.reads.values == ["a.png"])
    }

    @Test(
        "read answers each failure the DataSource reports as it is",
        arguments: [
            StillImageProblem.unreadable(path: "p.png"),
            .tooLarge(limit: 1_024),
            .notAnImage(path: "p.png"),
            .dimensionsOutOfRange(width: 0, height: 4),
            .unwritable(path: "p.png"),
        ])
    func readAnswersTheDataSourceFailure(problem: StillImageProblem) async {
        let dataSource = FakeStillImages()
        dataSource.script(.failure(problem), for: "p.png")
        let subject = makeSubject(dataSource)

        let result = await subject.read("p.png")

        #expect(result == .failure(problem))
        #expect(dataSource.reads.values == ["p.png"])
    }

    @Test("write hands the image and the path to the DataSource once, and answers success")
    func writeHandsTheImageOnce() async {
        let dataSource = FakeStillImages()
        let subject = makeSubject(dataSource)

        let result = await subject.write(Self.photo, to: "out.png")

        #expect(Self.problem(of: result) == nil)
        #expect(dataSource.writes.values == [FakeStillImages.StillImageWrite(path: "out.png", image: Self.photo)])
    }

    @Test("write answers the unwritable failure the DataSource reports as it is")
    func writeAnswersTheDataSourceFailure() async {
        let dataSource = FakeStillImages()
        dataSource.failWrites(with: .unwritable(path: "missing/out.png"))
        let subject = makeSubject(dataSource)

        let result = await subject.write(Self.photo, to: "missing/out.png")

        #expect(Self.problem(of: result) == .unwritable(path: "missing/out.png"))
        #expect(dataSource.writes.count == 1)
    }

    @Test("the stillImageRepository dependency resolves the repository it is set to")
    func dependencyResolvesTheSetRepository() async {
        let fake = FakeStillImageRepository()
        fake.script(.success(Self.photo), for: "a.png")
        let resolved = withDependencies {
            $0.stillImageRepository = fake
        } operation: {
            StillImageRepositoryProbe().repository
        }

        #expect(await resolved.read("a.png") == .success(Self.photo))
        #expect(fake.reads.values == ["a.png"])
    }
}

/// Resolves `\.stillImageRepository` the way a UseCase does, so the test reaches the key through `@Dependency`.
private struct StillImageRepositoryProbe {
    @Dependency(\.stillImageRepository) var repository
}

@Suite("FakeStillImageRepository")
struct FakeStillImageRepositoryTests {
    private static let photo = StillImage(width: 2, height: 2, bgra: [UInt8](repeating: 0x7F, count: 16))

    /// The problem a write answered with, `nil` when it succeeded.
    private static func problem(of result: Result<Void, StillImageProblem>) -> StillImageProblem? {
        if case .failure(let problem) = result { return problem }
        return nil
    }

    @Test("a scripted result is what read answers for its path, and the read is recorded")
    func scriptedResultIsAnswered() async {
        let fake = FakeStillImageRepository()
        fake.script(.success(Self.photo), for: "a.png")

        let result = await fake.read("a.png")

        #expect(result == .success(Self.photo))
        #expect(fake.reads.values == ["a.png"])
    }

    @Test("failWrites makes a write fail and still record it, and nil makes writes succeed again")
    func failWritesIsRecordedAndCanBeLifted() async {
        let fake = FakeStillImageRepository()

        fake.failWrites(with: .unwritable(path: "p.png"))
        let failed = await fake.write(Self.photo, to: "p.png")
        fake.failWrites(with: nil)
        let restored = await fake.write(Self.photo, to: "p.png")

        #expect(Self.problem(of: failed) == .unwritable(path: "p.png"))
        #expect(Self.problem(of: restored) == nil)
        #expect(
            fake.writes.values == [
                FakeStillImageRepository.Write(path: "p.png", image: Self.photo),
                FakeStillImageRepository.Write(path: "p.png", image: Self.photo),
            ])
    }
}
