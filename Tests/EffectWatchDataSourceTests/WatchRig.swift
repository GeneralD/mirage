import Dependencies
import Domain
import EffectWatchDataSource
import TestDoubles
import TestSupport

/// The subject over the fakes, with the test holding every end: the watches
/// (`gateway.fire(path)`, and `keeper.callbacks` for an event that arrives after the watch was
/// stopped), the clock (`clock.advance(by:)`) and the developer log.
///
/// The clock is a `GatedClock`, not a `TestClock`: an event travels from the watch's
/// callback through the debouncing task to a sleep on the clock, and a clock that cannot
/// say when that sleep is parked would let `advance` run before it, which loses the
/// advance. `clock.sleepers` fires once a sleep is registered, so a test advances time
/// only when the subject is waiting on it; `parkedCount` is how many sleeps are still
/// waiting, which is how a test sees a quiet period run out (or not) without waiting for a
/// timer or a tick.
struct WatchRig: Sendable {
    let gateway = FakeFileWatchGateway()
    /// What the subject resolves as `fileWatchGateway`: `gateway` behind a wrapper that keeps each callback.
    let keeper: CallbackKeepingGateway
    let clock = GatedClock()
    let log = RecordingLog()
    let subject: EffectWatchDataSourceImpl

    /// What a listing of one package asks to be watched: the folder and the package
    /// directory as directories, the manifest and the shader as files.
    static let manifest = "/effects/a.lens/manifest.json"
    static let shader = "/effects/a.lens/effect.metal"
    static let onePackage = EffectWatchSet(directories: ["/effects", "/effects/a.lens"], files: [manifest, shader])

    init() {
        let keeper = CallbackKeepingGateway(wrapping: gateway)
        let clock = clock
        let log = log
        self.keeper = keeper
        subject = withDependencies {
            $0.fileWatchGateway = keeper
            $0.continuousClock = clock
            $0.developerLog = log
        } operation: {
            EffectWatchDataSourceImpl()
        }
    }

    /// Receives what `stream` yields in a task of its own, stamping each element with the
    /// clock's time when it arrives. A test advances the clock only after it has seen the
    /// element it expects, so the stamp is the time the advance that woke it moved to.
    func listen(to stream: AsyncStream<Void>, into heard: Collector<Duration>) -> Task<Void, Never> {
        let clock = clock
        return Task { for await _ in stream { heard.append(clock.now.offset) } }
    }

    /// Lets go of a consumer the way `EffectPackageRepository` lets go of a watch it
    /// replaced, and returns once the stream's termination has run: cancelling the task
    /// terminates the stream (stopping every watch) before iteration ends.
    func end(_ consumer: Task<Void, Never>) async {
        consumer.cancel()
        await consumer.value
    }
}
