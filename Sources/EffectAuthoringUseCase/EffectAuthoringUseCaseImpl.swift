import Dependencies
import Domain

/// The authoring policy of the command-line tool. `validate` answers what the Repository's check
/// answers, unchanged; `scaffold` answers the Repository's path, and wraps its problem as
/// `AuthoringFailure.scaffold`. It resolves the catalog Repository and nothing else.
public struct EffectAuthoringUseCaseImpl: EffectAuthoringUseCase, Sendable {
    @Dependency(\.effectPackageRepository) private var packages

    public init() {}

    public func validate(packageAt path: String) async -> Result<EffectSource, AuthoringFailure> {
        await packages.check(packageAt: path)
    }

    public func scaffold(named name: String, in folder: String) async -> Result<String, AuthoringFailure> {
        await packages.scaffold(named: name, in: folder).mapError { AuthoringFailure.scaffold($0) }
    }
}
