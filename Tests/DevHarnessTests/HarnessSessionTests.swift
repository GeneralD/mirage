import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import DevHarness

@MainActor
@Suite("HarnessSession", .timeLimit(.minutes(1)))
struct HarnessSessionTests {
    @Test("start launches the interactor once, with the 720p frame at the standard rate")
    func startLaunches() async {
        let rig = HarnessSessionRig()
        rig.subject.start()
        await rig.interactor.launches.waitForCount(1)

        #expect(rig.interactor.launches.values == [HarnessLaunch(descriptor: .hd720, frameRate: .standard)])
        #expect(rig.interactor.shutDowns.count == 0)
    }

    @Test("stop cancels a launch still waiting, then shuts the interactor down")
    func stopCancelsTheLaunch() async {
        let rig = HarnessSessionRig()
        rig.subject.start()
        await rig.interactor.launches.waitForCount(1)

        rig.subject.stop()

        #expect(rig.interactor.shutDowns.count == 1)
        await rig.interactor.cancelled.waitForCount(1)
    }

    @Test("stop before any start still shuts the interactor down")
    func stopWithoutStart() {
        let rig = HarnessSessionRig()
        rig.subject.stop()

        #expect(rig.interactor.shutDowns.count == 1)
        #expect(rig.interactor.launches.count == 0)
    }

    @Test("attach passes the window's view to the interactor")
    func attachPassesTheViewThrough() {
        let rig = HarnessSessionRig()
        let target = FakePreviewTargetHandle()
        rig.subject.attach(target)

        #expect(rig.interactor.attached.values == [ObjectIdentifier(target)])
    }
}

@MainActor
private struct HarnessSessionRig {
    let interactor = LaunchLeftOpen()
    let subject: HarnessSession

    init() {
        let interactor = interactor
        subject = withDependencies {
            $0.harnessInteractor = interactor
        } operation: {
            HarnessSession()
        }
    }
}

private struct HarnessLaunch: Equatable, Sendable {
    let descriptor: SurfaceDescriptor
    let frameRate: FrameRate
}

/// A `HarnessInteractor` whose launch waits, like an unanswered camera prompt,
/// until its task is cancelled; it records what reached it.
private final class LaunchLeftOpen: HarnessInteractor, Sendable {
    let launches = Collector<HarnessLaunch>()
    let cancelled = Collector<Void>()
    let shutDowns = Collector<Void>()
    let attached = Collector<ObjectIdentifier>()

    func launch(descriptor: SurfaceDescriptor, frameRate: FrameRate) async {
        launches.append(HarnessLaunch(descriptor: descriptor, frameRate: frameRate))
        if await suspendUntilCancelled() { cancelled.append(()) }
    }

    @MainActor
    func attach(_ target: any PreviewTargetHandle) {
        attached.append(ObjectIdentifier(target))
    }

    func shutDown() {
        shutDowns.append(())
    }
}
