import Dependencies

/// The entry of the command-line tool into the authoring policy (epic E9). It answers the three calls of
/// `EffectAuthoringUseCase` the same way; what the answer means to the user is the caller's to show.
public protocol EffectAuthoringInteractor: Sendable {
    /// Checks the `.lens` package at `path` and answers the source it provides, or the failure with its reason.
    func validate(packageAt path: String) async -> Result<EffectSource, AuthoringFailure>

    /// Creates a new package called `name` in `folder` and answers the path it was written at, or the failure.
    func scaffold(named name: String, in folder: String) async -> Result<String, AuthoringFailure>

    /// Renders the still image at `input` through `effect` into `output` and answers the size it was written at, or the failure.
    func render(_ effect: EffectReference, from input: String, to output: String) async -> Result<StillImageSize, AuthoringFailure>
}

public enum EffectAuthoringInteractorKey: TestDependencyKey {
    public static let testValue: any EffectAuthoringInteractor = UnimplementedEffectAuthoringInteractor()
}

extension DependencyValues {
    public var effectAuthoringInteractor: any EffectAuthoringInteractor {
        get { self[EffectAuthoringInteractorKey.self] }
        set { self[EffectAuthoringInteractorKey.self] = newValue }
    }
}

private struct UnimplementedEffectAuthoringInteractor: EffectAuthoringInteractor {
    func validate(packageAt path: String) async -> Result<EffectSource, AuthoringFailure> {
        reportIssue("EffectAuthoringInteractor.validate not implemented")
        return .failure(.packageNotFound(path: path))
    }

    func scaffold(named name: String, in folder: String) async -> Result<String, AuthoringFailure> {
        reportIssue("EffectAuthoringInteractor.scaffold not implemented")
        return .failure(.scaffold(.unwritable(path: folder)))
    }

    func render(_ effect: EffectReference, from input: String, to output: String) async -> Result<StillImageSize, AuthoringFailure> {
        reportIssue("EffectAuthoringInteractor.render not implemented")
        return .failure(.surfaceUnavailable)
    }
}
