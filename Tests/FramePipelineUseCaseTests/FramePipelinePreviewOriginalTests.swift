import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

@Suite("FramePipelineUseCaseImpl preview original", .timeLimit(.minutes(1)))
struct FramePipelinePreviewOriginalTests {
    @Test("the default pipeline presents every frame with no original, whether its pass succeeded or failed")
    func defaultPipelinePresentsNoOriginal() async throws {
        let rig = Rig(capacity: 4)
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()

        _ = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        let applied = try await rig.applyRequest(0)
        #expect(await rig.answer(applied, with: .success(())))

        _ = try #require(rig.emit(at: 2_000))
        rig.scheduler.tick()
        let failed = try await rig.applyRequest(1)
        #expect(await rig.answer(failed, with: .failure(.timeout)))

        // Checked first, so an empty preview fails the test instead of passing the check below vacuously.
        let presented = rig.preview.presented.values
        try #require(presented.count == 2, "both frames reached the preview")
        #expect(presented.allSatisfy { $0.original == nil }, "the pipeline passes no original to the preview")
    }
}
