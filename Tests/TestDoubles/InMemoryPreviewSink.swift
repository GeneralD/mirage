import Domain
import TestSupport

/// Stands in for the preview view: the target `InMemoryPreviewSink.attach` and
/// `FakePreviewGateway.prepare` accept; identity is the object itself.
public final class FakePreviewTargetHandle: PreviewTargetHandle, Sendable {
    public init() {}

    public var backing: AnyObject { self }
}

/// `PreviewSink` as the test sees it: records what was attached and detached and
/// every frame presented, in order, and holds each frame's completion until the
/// test releases it with `complete(_:)` — exactly once, in any order — so "the
/// preview is slower than the camera" is a sequence the test writes down.
/// With `holding: .onceAttached` it models a preview nobody has opened yet, or
/// has closed again: until a target is attached, and after the attached target
/// is detached, every frame completes inside `present`. The live sink is
/// looser: `PreviewDataSource` queues the frame on the executor and completes it
/// in that job, after `present` has returned, so this is the stricter
/// caller-still-inside-its-own-call case, and needs no executor.
public final class InMemoryPreviewSink: PreviewSink, Sendable {
    public struct Presentation: Sendable {
        public let id: Int
        public let frame: FrameRef
        /// The sink that issued it: ids restart at 1 per instance, so the id alone cannot tell a stranger's presentation.
        fileprivate let origin: ObjectIdentifier
    }

    /// From when a presentation's completion waits for the test.
    public enum Holding: Sendable {
        /// From the first `present` on: every completion waits for `complete(_:)`.
        case always
        /// While a target is attached. Before the first attach, and after the
        /// attached target is detached, every frame completes synchronously
        /// inside `present` (the live sink completes it in a later executor job;
        /// this is the stricter case: the caller is still inside its own call),
        /// and is recorded as completed.
        case onceAttached
    }

    private struct State {
        var nextID = 1
        var pending: [Int: @Sendable () -> Void] = [:]
        var attached: [FakePreviewTargetHandle] = []
        /// The target attached now; `nil` before any attach and once it is detached.
        var current: FakePreviewTargetHandle?
        var detached: [FakePreviewTargetHandle] = []
    }

    private let holding: Holding
    private let state = Locked(State())
    /// Every frame presented, in presentation order, completed or not.
    public let presented = Collector<Presentation>()

    public init(holding: Holding = .always) {
        self.holding = holding
    }

    /// Every attach of a fake target, in call order; the history is kept after a detach.
    public var attached: [FakePreviewTargetHandle] { state.current.attached }

    /// Every detach of a fake target, in call order, whether or not it let go of the attached one.
    public var detached: [FakePreviewTargetHandle] { state.current.detached }

    /// Frames presented and not yet completed, in presentation order.
    public var pending: [Presentation] {
        let ids = state.current.pending
        return presented.values.filter { ids[$0.id] != nil }
    }

    public nonisolated func attach(_ target: any PreviewTargetHandle) throws {
        let fake = try (target as? FakePreviewTargetHandle).orThrow(PreviewError.foreignTarget)
        state.withLock {
            $0.attached.append(fake)
            $0.current = fake
        }
    }

    /// Records a fake target's detach, and lets go of the target when it is the
    /// attached one. A target that is not a fake is ignored.
    public func detach(_ target: any PreviewTargetHandle) {
        guard let fake = target as? FakePreviewTargetHandle else { return }
        state.withLock {
            $0.detached.append(fake)
            if $0.current === fake { $0.current = nil }
        }
    }

    public func present(_ frame: FrameRef, completion: @escaping @Sendable () -> Void) {
        let (presentation, held) = state.withLock { state in
            let id = state.nextID
            state.nextID += 1
            let held = holding == .always || state.current != nil
            if held { state.pending[id] = completion }
            return (Presentation(id: id, frame: frame, origin: ObjectIdentifier(self)), held)
        }
        presented.append(presentation)
        guard !held else { return }
        completion()
    }

    /// Runs the frame's completion, once. `false` when the presentation is
    /// unknown, came from another sink, or was already completed (one that
    /// completed inside `present` included).
    @discardableResult
    public func complete(_ presentation: Presentation) -> Bool {
        guard presentation.origin == ObjectIdentifier(self) else { return false }
        guard let completion = state.withLock({ $0.pending.removeValue(forKey: presentation.id) }) else { return false }
        completion()
        return true
    }
}
