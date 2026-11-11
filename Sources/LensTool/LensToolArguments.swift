import Domain

/// Reads the arguments of the `lens` command-line tool into a `LensCommand`, or says why they make none.
/// Pure: the caller passes the arguments without the program name, and runs the command it gets back.
enum LensToolArguments {
    /// The command the arguments name. The first argument is the command; the rest is read from the front, and
    /// the first problem found is the answer. Once the whole line is read, a positional or an option still missing
    /// is named: the positional first, then the options in the order the usage lists them.
    static func parse(_ arguments: [String]) -> Result<LensCommand, LensUsageProblem> {
        guard let command = arguments.first else { return .failure(.noCommand) }
        let rest = arguments.dropFirst()
        switch command {
        case "help", "--help", "-h":
            guard let extra = rest.first else { return .success(.help) }
            return .failure(.unexpectedArgument(extra))
        case "validate":
            return validate(rest)
        case "new":
            return scaffold(rest)
        case "render":
            return render(rest)
        default:
            return .failure(.unknownCommand(command))
        }
    }

    // MARK: - Commands

    /// `validate <package>`: one positional argument and no option.
    private static func validate(_ arguments: ArraySlice<String>) -> Result<LensCommand, LensUsageProblem> {
        scan(arguments, positionalCount: 1, options: []).flatMap { scanned in
            required(scanned.positionals.first, named: "package").map { LensCommand.validate(path: $0) }
        }
    }

    /// `new <name> [--in <folder>]`: the folder is `.` when `--in` is not given.
    private static func scaffold(_ arguments: ArraySlice<String>) -> Result<LensCommand, LensUsageProblem> {
        scan(arguments, positionalCount: 1, options: ["--in"]).flatMap { scanned in
            required(scanned.positionals.first, named: "name").map { name in
                LensCommand.scaffold(name: name, folder: scanned.options["--in"] ?? ".")
            }
        }
    }

    /// `render <effect> --input <png> --output <png>`.
    private static func render(_ arguments: ArraySlice<String>) -> Result<LensCommand, LensUsageProblem> {
        scan(arguments, positionalCount: 1, options: ["--input", "--output"]).flatMap(renderCommand)
    }

    private static func renderCommand(_ scanned: Scanned) -> Result<LensCommand, LensUsageProblem> {
        switch (scanned.positionals.first, scanned.options["--input"], scanned.options["--output"]) {
        case (let effect?, let input?, let output?):
            return .success(.render(effect: reference(for: effect), input: input, output: output))
        case (nil, _, _):
            return .failure(.missingValue("effect"))
        case (_, nil, _):
            return .failure(.missingValue("--input"))
        case (_, _, nil):
            return .failure(.missingValue("--output"))
        }
    }

    // MARK: - Reading

    /// What reading one command's arguments found: its positional arguments in order, and the value of each
    /// option it takes.
    private struct Scanned {
        let positionals: [String]
        let options: [String: String]
    }

    /// Reads `arguments` from the front. An option takes the argument after it as its value, which may not start
    /// with `-`. An argument that starts with `-` and is not one of `options` is an unknown option, and a
    /// positional argument beyond `positionalCount` is unexpected. The first of these problems is the answer.
    private static func scan(
        _ arguments: ArraySlice<String>,
        positionalCount: Int,
        options: [String],
        positionals: [String] = [],
        values: [String: String] = [:]
    ) -> Result<Scanned, LensUsageProblem> {
        guard let head = arguments.first else {
            return .success(Scanned(positionals: positionals, options: values))
        }
        let rest = arguments.dropFirst()
        if options.contains(head) {
            guard values[head] == nil else { return .failure(.duplicateOption(head)) }
            guard let value = rest.first, !value.hasPrefix("-") else { return .failure(.missingValue(head)) }
            return scan(
                rest.dropFirst(), positionalCount: positionalCount, options: options,
                positionals: positionals, values: values.merging([head: value]) { current, _ in current })
        }
        if head.hasPrefix("-") { return .failure(.unknownOption(head)) }
        guard positionals.count < positionalCount else { return .failure(.unexpectedArgument(head)) }
        return scan(
            rest, positionalCount: positionalCount, options: options,
            positionals: positionals + [head], values: values)
    }

    /// The value of a positional argument or an option that the command needs, or the problem that it is missing.
    private static func required(_ value: String?, named name: String) -> Result<String, LensUsageProblem> {
        guard let value else { return .failure(.missingValue(name)) }
        return .success(value)
    }

    /// A `.lens` package when the effect ends in `.lens` once its trailing `/` are dropped, otherwise a bundled
    /// effect. The package keeps the path as it was typed, trailing `/` included.
    private static func reference(for effect: String) -> EffectReference {
        let stem = String(effect.reversed().drop(while: { $0 == "/" }).reversed())
        return stem.hasSuffix(".lens") ? .package(path: effect) : .bundled(name: effect)
    }
}
