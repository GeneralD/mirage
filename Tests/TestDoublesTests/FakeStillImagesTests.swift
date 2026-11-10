import Domain
import TestDoubles
import Testing

@Suite("FakeStillImages")
struct FakeStillImagesTests {
    private static let photo = StillImage(width: 2, height: 2, bgra: [UInt8](repeating: 0x7F, count: 16))

    /// The problem a write answered with, `nil` when it succeeded.
    private static func problem(of result: Result<Void, StillImageProblem>) -> StillImageProblem? {
        if case .failure(let problem) = result { return problem }
        return nil
    }

    @Test("a scripted image is what read answers for its path, and the read is recorded")
    func scriptedImageIsAnswered() async {
        let fake = FakeStillImages()
        fake.script(.success(Self.photo), for: "a.png")

        let result = await fake.read("a.png")

        #expect(result == .success(Self.photo))
        #expect(fake.reads.values == ["a.png"])
    }

    @Test("a scripted failure is what read answers for its path, and is recorded like a success")
    func scriptedFailureIsAnswered() async {
        let fake = FakeStillImages()
        fake.script(.failure(.notAnImage(path: "b.png")), for: "b.png")

        let result = await fake.read("b.png")

        #expect(result == .failure(.notAnImage(path: "b.png")))
        #expect(fake.reads.values == ["b.png"])
    }

    @Test("a path with no script reports an issue and answers unreadable, and the read is still recorded")
    func unscriptedPathReportsAnIssue() async {
        let fake = FakeStillImages()

        await withKnownIssue {
            let result = await fake.read("missing.png")
            #expect(result == .failure(.unreadable(path: "missing.png")))
        }

        #expect(fake.reads.values == ["missing.png"])
    }

    @Test("a write succeeds and is recorded with its path and its image")
    func writeSucceedsAndIsRecorded() async {
        let fake = FakeStillImages()

        let result = await fake.write(Self.photo, to: "out.png")

        #expect(Self.problem(of: result) == nil)
        #expect(fake.writes.values == [FakeStillImages.StillImageWrite(path: "out.png", image: Self.photo)])
    }

    @Test("failWrites makes a write fail and still record it, and nil makes writes succeed again")
    func failWritesIsRecordedAndCanBeLifted() async {
        let fake = FakeStillImages()

        fake.failWrites(with: .unwritable(path: "p.png"))
        let failed = await fake.write(Self.photo, to: "p.png")
        fake.failWrites(with: nil)
        let restored = await fake.write(Self.photo, to: "p.png")

        #expect(Self.problem(of: failed) == .unwritable(path: "p.png"))
        #expect(Self.problem(of: restored) == nil)
        #expect(fake.writes.count == 2)
    }
}
