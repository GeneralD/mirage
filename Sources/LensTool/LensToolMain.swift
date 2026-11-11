import Dependencies
import Domain
import Presenters

/// The entry of the `lens` command line: it runs the command its arguments name through the authoring interactor
/// and shows the answer through the console. What the text says is `AuthoringReportText`'s; this type only chooses
/// which text goes to which stream and which exit code the run ends with.
struct LensToolMain: Sendable {
    @Dependency(\.effectAuthoringInteractor) private var interactor
    @Dependency(\.consoleWriter) private var console

    init() {}

    /// Runs the command the arguments name, given without the program name, and answers the exit code: 0 when the
    /// command succeeds or `help` is asked for, 1 when the command fails, 2 when the arguments name no command.
    func run(_ arguments: [String]) async -> Int32 {
        switch LensToolArguments.parse(arguments) {
        case .failure(let problem):
            console.errorLine(AuthoringReportText.usage(problem))
            console.errorLine(AuthoringReportText.help)
            return 2
        case .success(let command):
            return await execute(command)
        }
    }

    // MARK: - Commands

    private func execute(_ command: LensCommand) async -> Int32 {
        switch command {
        case .help:
            console.line(AuthoringReportText.help)
            return 0
        case .validate(let path):
            switch await interactor.validate(packageAt: path) {
            case .success(let source):
                console.line(AuthoringReportText.validated(source))
                return 0
            case .failure(let failure):
                return report(failure)
            }
        case .scaffold(let name, let folder):
            switch await interactor.scaffold(named: name, in: folder) {
            case .success(let path):
                console.line(AuthoringReportText.scaffolded(path: path))
                return 0
            case .failure(let failure):
                return report(failure)
            }
        case .render(let effect, let input, let output):
            switch await interactor.render(effect, from: input, to: output) {
            case .success(let size):
                console.line(AuthoringReportText.rendered(effect: effect, output: output, size: size))
                return 0
            case .failure(let failure):
                return report(failure)
            }
        }
    }

    /// Writes a failure to standard error and answers the exit code of a failed command.
    private func report(_ failure: AuthoringFailure) -> Int32 {
        console.errorLine(AuthoringReportText.failure(failure))
        return 1
    }
}
