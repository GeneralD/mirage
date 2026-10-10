import Domain

/// How an effect's source becomes the source the compiler sees, and how the
/// compiler's locations are brought back to the author's file. Pure functions.
///
/// The assembled source is the prelude, then `#line 1 "effect"`, then the
/// author's source verbatim. The directive makes the compiler number the
/// author's lines from 1 under the file name `effect`, so a diagnostic already
/// reads `effect:<author line>:<column>:` (proven on the real compiler by the
/// `MetalGateway smoke` suite). Locations still given against the assembled
/// source (`program_source:<line>:`) are rewritten as well: inside the author's
/// part to `effect:<author line>:` — the safety net should a compiler ignore the
/// directive — and inside the prelude to `prelude:<line>:`, so a note pointing
/// at a prelude declaration says so. Only a location that opens a diagnostic line
/// is rewritten: the compiler echoes the failing source line verbatim, so the
/// same text inside that excerpt or inside a message is the author's and is kept.
public enum ShaderSourceAssembly {
    /// The file name the author's lines are reported under.
    public static let authorFileName = "effect"
    /// The file name prelude locations are rewritten to.
    public static let preludeFileName = "prelude"

    /// The `#line` directive between the prelude and the author's first line.
    public static let lineDirective = "#line 1 \"\(authorFileName)\"\n"

    /// Lines of the assembled source before the author's first line: the
    /// prelude's lines plus the directive's. Author line `n` is assembled line
    /// `authorLineOffset + n`.
    public static let authorLineOffset = ShaderPrelude.source.filter { $0 == "\n" }.count + 1

    /// The prelude, the directive and `authorSource`, in that order.
    public static func assemble(_ authorSource: String) -> String {
        ShaderPrelude.source + lineDirective + authorSource
    }

    /// `diagnostics` with every `program_source:<line>:` location rewritten to the
    /// author's file or the prelude; the code is kept.
    public static func authorRelative(_ diagnostics: ShaderDiagnostics) -> ShaderDiagnostics {
        ShaderDiagnostics(message: authorRelative(diagnostics.message), code: diagnostics.code)
    }

    /// `message` with every `program_source:<line>:` location at the start of a
    /// line rewritten; any other text, `effect:<line>:` locations and the same
    /// text in the middle of a line included, is left as it is.
    public static func authorRelative(_ message: String) -> String {
        message.replacing(#/^program_source:(\d+):/#.anchorsMatchLineEndings()) { match in
            Int(match.output.1).map(location(ofAssembledLine:)) ?? String(match.output.0)
        }
    }

    /// `effect:<n>:` for author line `n`, `prelude:<line>:` for a line before it
    /// (the directive's own line included: it is the engine's text, not the author's).
    static func location(ofAssembledLine line: Int) -> String {
        line > authorLineOffset ? "\(authorFileName):\(line - authorLineOffset):" : "\(preludeFileName):\(line):"
    }
}
