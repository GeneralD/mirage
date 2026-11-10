import Dependencies
import Domain
import PreviewRepository
import TestDoubles
import TestSupport
import Testing

@Suite("PreviewRepositoryImpl", .timeLimit(.minutes(1)))
struct PreviewRepositoryTests {
    private let renderer = SpyPreviewRenderer()
    private let frame = FrameRef(token: SurfaceToken(index: 2, generation: 7), descriptor: .hd720, presentationTime: HostTimestamp(nanoseconds: 42))
    private let original = FrameRef(
        token: SurfaceToken(index: 5, generation: 3), descriptor: .hd720, presentationTime: HostTimestamp(nanoseconds: 41))

    private func makeSubject() -> PreviewRepositoryImpl {
        withDependencies {
            $0.previewRenderer = renderer
        } operation: {
            PreviewRepositoryImpl()
        }
    }

    @Test("attach forwards the target to the renderer")
    func attachForwards() async throws {
        let subject = makeSubject()
        let target = FakePreviewTargetHandle()
        try await MainActor.run { try subject.attach(target) }

        #expect(renderer.attached.values.map(ObjectIdentifier.init) == [ObjectIdentifier(target)])
    }

    @Test("a refused attach is rethrown unchanged")
    func attachRethrows() async {
        let subject = makeSubject()
        renderer.attachError.set(GPUError.noDevice)
        await #expect(throws: GPUError.noDevice) { try await MainActor.run { try subject.attach(FakePreviewTargetHandle()) } }
    }

    @Test("present passes the frame and its original to the renderer unchanged, and the renderer's completion reaches the caller exactly once")
    func presentForwards() throws {
        let completions = Collector<Void>()
        makeSubject().present(frame, original: original) { completions.append(()) }

        let presentation = try #require(renderer.presented.values.first)
        #expect(renderer.presented.values.map(\.frame) == [frame])
        #expect(presentation.original == original, "the repository hands the original on, not the frame again or nil")
        #expect(completions.count == 0, "the repository adds no completion of its own")
        presentation.completion()
        #expect(completions.count == 1)
    }

    @Test("present with no original passes nil to the renderer")
    func presentForwardsNoOriginal() throws {
        makeSubject().present(frame, original: nil) {}

        let presentation = try #require(renderer.presented.values.first)
        #expect(presentation.frame == frame)
        #expect(presentation.original == nil)
    }

    @Test("detach hands the target to the renderer unchanged, exactly once")
    func detachForwards() {
        let subject = makeSubject()
        let target = FakePreviewTargetHandle()
        subject.detach(target)

        #expect(renderer.detached.values == [ObjectIdentifier(target)])
    }
}

/// The renderer as the repository suite needs it: records what it is handed and
/// holds each completion for the test to run.
private final class SpyPreviewRenderer: PreviewRenderer, Sendable {
    struct Presentation: Sendable {
        let frame: FrameRef
        let original: FrameRef?
        let completion: @Sendable () -> Void
    }

    let attached = Collector<FakePreviewTargetHandle>()
    let detached = Collector<ObjectIdentifier>()
    let presented = Collector<Presentation>()
    let attachError = Locked<(any Error)?>(nil)

    nonisolated func attach(_ target: any PreviewTargetHandle) throws {
        if let error = attachError.current { throw error }
        attached.append(try (target as? FakePreviewTargetHandle).orThrow(PreviewError.foreignTarget))
    }

    func detach(_ target: any PreviewTargetHandle) {
        detached.append(ObjectIdentifier(target))
    }

    func present(_ frame: FrameRef, original: FrameRef?, completion: @escaping @Sendable () -> Void) {
        presented.append(Presentation(frame: frame, original: original, completion: completion))
    }
}
