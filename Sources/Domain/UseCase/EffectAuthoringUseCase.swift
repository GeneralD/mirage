import Dependencies

/// The authoring policy of the command-line tool (epic E9): checking a `.lens` package without a
/// camera, and scaffolding a new one. The checks and the files are the Repository's; this port is
/// what the tool asks for and what it is answered, failures as the closed `AuthoringFailure` set the
/// tool shows to its user.
public protocol EffectAuthoringUseCase: Sendable {
    /// Reads the `.lens` package at `path` and compiles its shader. A package that compiles answers
    /// the source it provides; a missing or unusable package, or a shader that does not compile, answers
    /// the failure with the reason, unchanged.
    func validate(packageAt path: String) async -> Result<EffectSource, AuthoringFailure>

    /// Creates a new package called `name` in `folder` and answers the path it was written at. A package
    /// that cannot be created answers `.scaffold(problem)` with the reason.
    func scaffold(named name: String, in folder: String) async -> Result<String, AuthoringFailure>

    /// Renders the still image at `input` through `effect` once and writes the result to `output` as a PNG,
    /// answering the size it was written at. The effect runs with its default parameters, at time zero and
    /// frame zero; no camera is used. An effect named by a package is checked first, and its failure is
    /// answered unchanged; a failure of the image, the runtime or the output is answered with its reason.
    func render(_ effect: EffectReference, from input: String, to output: String) async -> Result<StillImageSize, AuthoringFailure>
}

public enum EffectAuthoringUseCaseKey: TestDependencyKey {
    public static let testValue: any EffectAuthoringUseCase = UnimplementedEffectAuthoringUseCase()
}

extension DependencyValues {
    public var effectAuthoringUseCase: any EffectAuthoringUseCase {
        get { self[EffectAuthoringUseCaseKey.self] }
        set { self[EffectAuthoringUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedEffectAuthoringUseCase: EffectAuthoringUseCase {
    func validate(packageAt path: String) async -> Result<EffectSource, AuthoringFailure> {
        reportIssue("EffectAuthoringUseCase.validate not implemented")
        return .failure(.packageNotFound(path: path))
    }

    func scaffold(named name: String, in folder: String) async -> Result<String, AuthoringFailure> {
        reportIssue("EffectAuthoringUseCase.scaffold not implemented")
        return .failure(.scaffold(.unwritable(path: folder)))
    }

    func render(_ effect: EffectReference, from input: String, to output: String) async -> Result<StillImageSize, AuthoringFailure> {
        reportIssue("EffectAuthoringUseCase.render not implemented")
        return .failure(.surfaceUnavailable)
    }
}
