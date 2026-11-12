import Dependencies
import Domain
import TestSupport

/// `EffectAuthoringUseCase` the test scripts answers into. `scriptValidate(_:for:)` sets what `validate`
/// answers for one path, `scriptScaffold(_:)` what `scaffold` answers until it is scripted again, and
/// `scriptRender(_:)` what `render` answers until it is scripted again. Each call is recorded:
/// `validateRequests` holds the paths in call order, `scaffoldRequests` the name and the folder, and
/// `renderRequests` the effect and the two paths. A call nobody scripted is a reported issue, answering
/// `.packageNotFound(path:)` for `validate`, `.scaffold(.unwritable(path:))` for `scaffold` and
/// `.surfaceUnavailable` for `render`.
public final class FakeEffectAuthoringUseCase: EffectAuthoringUseCase, Sendable {
    /// One `scaffold(named:in:)` call: the name and the folder it was asked for.
    public struct ScaffoldRequest: Sendable, Equatable {
        public let name: String
        public let folder: String

        public init(name: String, folder: String) {
            self.name = name
            self.folder = folder
        }
    }

    /// One `render(_:from:to:)` call: the effect, the input path and the output path it was asked for.
    public struct RenderRequest: Sendable, Equatable {
        public let effect: EffectReference
        public let input: String
        public let output: String

        public init(effect: EffectReference, input: String, output: String) {
            self.effect = effect
            self.input = input
            self.output = output
        }
    }

    private struct State {
        var validates: [String: Result<EffectSource, AuthoringFailure>] = [:]
        var scaffoldResult: Result<String, AuthoringFailure>? = nil
        var renderResult: Result<StillImageSize, AuthoringFailure>? = nil
    }

    private let state: Locked<State>
    /// The paths `validate` was asked for, in call order.
    public let validateRequests = Collector<String>()
    /// The name and folder each `scaffold` call was asked for, in call order.
    public let scaffoldRequests = Collector<ScaffoldRequest>()
    /// The effect and the paths each `render` call was asked for, in call order.
    public let renderRequests = Collector<RenderRequest>()

    public init() {
        state = Locked(State())
    }

    /// Makes `validate(packageAt: path)` answer `result`.
    public func scriptValidate(_ result: Result<EffectSource, AuthoringFailure>, for path: String) {
        state.withLock { $0.validates[path] = result }
    }

    /// Makes `scaffold(named:in:)` answer `result` from now on, until it is scripted again.
    public func scriptScaffold(_ result: Result<String, AuthoringFailure>) {
        state.withLock { $0.scaffoldResult = result }
    }

    /// Makes `render(_:from:to:)` answer `result` from now on, until it is scripted again.
    public func scriptRender(_ result: Result<StillImageSize, AuthoringFailure>) {
        state.withLock { $0.renderResult = result }
    }

    public func validate(packageAt path: String) async -> Result<EffectSource, AuthoringFailure> {
        validateRequests.append(path)
        guard let result = state.withLock({ $0.validates[path] }) else {
            reportIssue("FakeEffectAuthoringUseCase: nothing scripted")
            return .failure(.packageNotFound(path: path))
        }
        return result
    }

    public func scaffold(named name: String, in folder: String) async -> Result<String, AuthoringFailure> {
        scaffoldRequests.append(ScaffoldRequest(name: name, folder: folder))
        guard let result = state.withLock({ $0.scaffoldResult }) else {
            reportIssue("FakeEffectAuthoringUseCase: nothing scripted")
            return .failure(.scaffold(.unwritable(path: folder)))
        }
        return result
    }

    public func render(_ effect: EffectReference, from input: String, to output: String) async -> Result<StillImageSize, AuthoringFailure> {
        renderRequests.append(RenderRequest(effect: effect, input: input, output: output))
        guard let result = state.withLock({ $0.renderResult }) else {
            reportIssue("FakeEffectAuthoringUseCase: nothing scripted")
            return .failure(.surfaceUnavailable)
        }
        return result
    }
}
