import Domain

/// The words the authoring command (`lens-tool`) prints, as pure functions of what the authoring use
/// case answers, so that the command's entry point only chooses which text to print.
public enum AuthoringReportText {
    /// `"<name>: OK, <phrase>"` for a package that validates; the phrase counts its parameters.
    public static func validated(_ source: EffectSource) -> String {
        "\(source.name): OK, \(phrase(parameterCount: source.parameters.count))"
    }

    /// The line after a package was created at `path`.
    public static func scaffolded(path: String) -> String {
        "Created \(path)"
    }

    /// The line after an image was rendered: where it went, its size, and the effect's label
    /// (the bundled name, or the path of the package).
    public static func rendered(effect: EffectReference, output: String, size: StillImageSize) -> String {
        "Wrote \(output) (\(size.width)x\(size.height)) with \(label(of: effect))"
    }

    /// The line for a failure. Every line starts with `error: `.
    public static func failure(_ failure: AuthoringFailure) -> String {
        switch failure {
        case .packageNotFound(let path): "error: \(path) is not a directory"
        case .package(let problem): "error: " + MenuBarText.reason(problem)
        case .compile(let message): "error: the shader does not compile\n\(message)"
        case .bundledEffectNotFound(let name): "error: no bundled effect is named \"\(name)\""
        case .image(let problem): imageFailure(problem)
        case .scaffold(let problem): scaffoldFailure(problem)
        case .effect(let problem): "error: the effect failed: " + MenuBarText.reason(problem)
        case .surfaceUnavailable: "error: no surface could be allocated for the image"
        }
    }

    /// The line for a usage error. Every line starts with `error: `.
    public static func usage(_ problem: LensUsageProblem) -> String {
        switch problem {
        case .noCommand: "error: no command given"
        case .unknownCommand(let command): "error: unknown command \"\(command)\""
        case .missingValue(let name): "error: missing \(name)"
        case .unexpectedArgument(let argument): "error: unexpected argument \"\(argument)\""
        case .unknownOption(let option): "error: unknown option \(option)"
        case .duplicateOption(let option): "error: \(option) was given more than once"
        }
    }

    /// The usage text the tool shows for `help`: the lines as they are printed, with one newline at the end.
    public static let help = """
        usage: lens-tool <command> [options]

        commands:
          validate <package>                              check a .lens package and compile its shader
          new <name> [--in <folder>]                      create a .lens package from a template
          render <effect> --input <png> --output <png>    run an effect over an image file
          help                                            show this message

        <effect> is a .lens package path or the name of a bundled effect.

        """

    private static func phrase(parameterCount count: Int) -> String {
        switch count {
        case 0: "no parameters"
        case 1: "1 parameter"
        default: "\(count) parameters"
        }
    }

    private static func label(of effect: EffectReference) -> String {
        switch effect {
        case .bundled(let name): name
        case .package(let path): path
        }
    }

    private static func imageFailure(_ problem: StillImageProblem) -> String {
        switch problem {
        case .unreadable(let path): "error: cannot read \(path)"
        case .tooLarge(let limit): "error: the image file is larger than \(limit) bytes"
        case .notAnImage(let path): "error: \(path) is not an image the tool can read"
        case .dimensionsOutOfRange(let width, let height): "error: an image of \(width)x\(height) pixels is not supported"
        case .unwritable(let path): "error: cannot write \(path)"
        }
    }

    private static func scaffoldFailure(_ problem: ScaffoldProblem) -> String {
        switch problem {
        case .invalidName(let name):
            "error: \"\(name)\" is not a valid name (1 to 64 letters, digits, spaces, - or _, starting with a letter or digit)"
        case .alreadyExists(let path): "error: \(path) already exists"
        case .unwritable(let path): "error: cannot write \(path)"
        }
    }
}
