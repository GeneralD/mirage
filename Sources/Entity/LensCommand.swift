/// How an effect to render is named: a bundled effect by the name it shows in the menu, or a package
/// by the path of its `.lens` folder.
public enum EffectReference: Sendable, Hashable {
    /// An effect bundled with the app, by its display name.
    case bundled(name: String)
    /// A `.lens` package, by the path of its folder.
    case package(path: String)
}

/// A command of the `lens` CLI, as its arguments were parsed. Closed so that every command is handled.
public enum LensCommand: Sendable, Hashable {
    /// Check the `.lens` package at `path` offline, without a camera.
    case validate(path: String)
    /// Create a new package called `name` in the folder `folder`.
    case scaffold(name: String, folder: String)
    /// Render the still image `input` through `effect` into `output`.
    case render(effect: EffectReference, input: String, output: String)
    /// Show the usage text.
    case help
}

/// Why the arguments of the `lens` CLI do not make a `LensCommand`. Closed so that every usage error
/// is shown to the user the same way.
public enum LensUsageProblem: Error, Sendable, Hashable {
    /// No command was given.
    case noCommand
    /// The first argument is not a command; the payload is that argument.
    case unknownCommand(String)
    /// A required argument or option value is missing; the payload names it, for example `"package"`
    /// or `"--input"`.
    case missingValue(String)
    /// An argument that no command takes; the payload is that argument.
    case unexpectedArgument(String)
    /// An option that the command does not take; the payload is that option.
    case unknownOption(String)
    /// An option given more than once; the payload is that option.
    case duplicateOption(String)
}
