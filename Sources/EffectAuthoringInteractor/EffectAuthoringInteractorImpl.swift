import Dependencies
import Domain

/// The command-line tool's entry into the authoring UseCase. Each call answers what the UseCase answers, unchanged,
/// and leaves one developer log line about it. No error log line is written: the tool shows the answer itself.
public struct EffectAuthoringInteractorImpl: EffectAuthoringInteractor, Sendable {
    @Dependency(\.effectAuthoringUseCase) private var useCase
    @Dependency(\.developerLog) private var developerLog

    public init() {}

    public func validate(packageAt path: String) async -> Result<EffectSource, AuthoringFailure> {
        let result = await useCase.validate(packageAt: path)
        switch result {
        case .success(let source):
            developerLog.record(.effect, "validated package at \(path): \(source.name)")
        case .failure(let failure):
            developerLog.record(.effect, "validation of \(path) failed: \(String(describing: failure))")
        }
        return result
    }

    public func scaffold(named name: String, in folder: String) async -> Result<String, AuthoringFailure> {
        let result = await useCase.scaffold(named: name, in: folder)
        switch result {
        case .success(let created):
            developerLog.record(.effect, "scaffolded \(name) at \(created)")
        case .failure(let failure):
            developerLog.record(.effect, "scaffold of \(name) in \(folder) failed: \(String(describing: failure))")
        }
        return result
    }

    public func render(_ effect: EffectReference, from input: String, to output: String) async -> Result<StillImageSize, AuthoringFailure> {
        let result = await useCase.render(effect, from: input, to: output)
        switch result {
        case .success(let size):
            developerLog.record(.effect, "rendered \(String(describing: effect)) from \(input) to \(output): \(size.width)x\(size.height)")
        case .failure(let failure):
            developerLog.record(.effect, "render from \(input) to \(output) failed: \(String(describing: failure))")
        }
        return result
    }
}
