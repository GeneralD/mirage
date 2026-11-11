import AppRouter
import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("AppRouter: the camera menu", .timeLimit(.minutes(1)))
struct AppRouterCameraMenuTests {
    // MARK: - The Presenter

    @Test("by default cameraMenuPresenter is nil, and the camera menu's factory is not called")
    func absentByDefault() {
        let builds = Collector<ObjectIdentifier>()
        let router = withDependencies {
            $0.effectInteractor = FakeEffectInteractor(state: .fixture([.fixture(.bundled("Chromatic Grain"))]))
            $0.controlsInteractor = FakeControlsInteractor()
            $0.cameraSelectionInteractor = FakeCameraSelectionInteractor(state: .empty)
        } operation: {
            AppRouter(makeCameraMenuPresenter: {
                let presenter = CameraMenuPresenter()
                builds.append(ObjectIdentifier(presenter))
                return presenter
            })
        }

        #expect(router.cameraMenuPresenter == nil)
        #expect(builds.values.isEmpty)
    }

    @Test("showsCameraMenu makes the camera menu's Presenter once, and every read of it is that one")
    func enabledMakesOnePresenter() {
        let builds = Collector<ObjectIdentifier>()
        let router = makeRouter(camera: FakeCameraSelectionInteractor(state: .empty), builds: builds, showsCameraMenu: true)

        let reads = (0..<3).map { _ in router.cameraMenuPresenter.map { ObjectIdentifier($0) } }
        router.start()
        router.stop()
        let readAfterwards = router.cameraMenuPresenter.map { ObjectIdentifier($0) }

        #expect(builds.values.count == 1)
        #expect((reads + [readAfterwards]).allSatisfy { $0 == builds.values.first })
    }

    // MARK: - Lifecycle

    @Test("start starts the camera Interactor once, and stop stops it")
    func startAndStopReachTheCameraInteractor() {
        let camera = FakeCameraSelectionInteractor(state: .empty)
        let router = makeRouter(camera: camera, builds: Collector<ObjectIdentifier>(), showsCameraMenu: true)

        router.start()
        router.start()
        #expect(camera.starts.count == 1)
        #expect(camera.stops.count == 0)

        router.stop()
        #expect(camera.stops.count == 1)
    }

    @Test("with showsCameraMenu false, start and stop never touch the camera Interactor")
    func offNeverTouchesTheCameraInteractor() {
        let camera = FakeCameraSelectionInteractor(state: .empty)
        let router = makeRouter(camera: camera, builds: Collector<ObjectIdentifier>(), showsCameraMenu: false)

        router.start()
        router.stop()

        #expect(camera.starts.count == 0)
        #expect(camera.stops.count == 0)
    }
}

/// A Router built inside `withDependencies`, so its Presenters talk to the fakes: the menu bar over a
/// `FakeEffectInteractor` and a `FakeControlsInteractor`, the camera menu over `camera`. The camera menu's
/// factory records each Presenter it makes in `builds`.
@MainActor
private func makeRouter(
    camera: FakeCameraSelectionInteractor,
    builds: Collector<ObjectIdentifier>,
    showsCameraMenu: Bool
) -> AppRouter {
    withDependencies {
        $0.effectInteractor = FakeEffectInteractor(state: .fixture([.fixture(.bundled("Chromatic Grain"))]))
        $0.controlsInteractor = FakeControlsInteractor()
        $0.cameraSelectionInteractor = camera
    } operation: {
        AppRouter(
            makeCameraMenuPresenter: {
                let presenter = CameraMenuPresenter()
                builds.append(ObjectIdentifier(presenter))
                return presenter
            },
            showsCameraMenu: showsCameraMenu)
    }
}
