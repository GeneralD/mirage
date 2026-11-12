/// Why a scaffold command could not create a package. Closed so that every consumer enumerates it.
public enum ScaffoldProblem: Error, Sendable, Hashable {
    /// The name given is not usable as a package name.
    case invalidName(String)
    /// Something already exists at `path`, so nothing is written over it.
    case alreadyExists(path: String)
    /// The package cannot be written at `path` (a missing folder, or no permission).
    case unwritable(path: String)
}

/// Why an authoring command (validate, scaffold, render) failed. This is the closed set of failures
/// the CLI shows to the user. Adding a case also changes the text type in Presenters, which turns the
/// case into its words, so the two change together.
public enum AuthoringFailure: Error, Sendable, Hashable {
    /// No package folder exists at `path`.
    case packageNotFound(path: String)
    /// The package folder is there but cannot be used, for the reason given.
    case package(EffectPackageProblem)
    /// The shader did not compile; `message` is the compiler's text.
    case compile(message: String)
    /// No effect bundled with the app has the name given.
    case bundledEffectNotFound(name: String)
    /// A still image could not be read or written.
    case image(StillImageProblem)
    /// A package could not be scaffolded.
    case scaffold(ScaffoldProblem)
    /// The effect did not produce a frame.
    case effect(EffectFailure)
    /// No surface could be obtained to draw on.
    case surfaceUnavailable
}
