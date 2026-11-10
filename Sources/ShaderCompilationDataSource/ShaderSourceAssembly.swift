import Domain

/// How an effect's source becomes the source the compiler sees, and how the
/// compiler's locations are brought back to the author's file. Pure functions.
///
/// The assembled source is the prelude, then one generated line declaring the
/// effect's `Parameters` struct, then `#line 1 "effect"`, then the author's
/// source verbatim. The directive makes the compiler number the
/// author's lines from 1 under the file name `effect`, so a diagnostic already
/// reads `effect:<author line>:<column>:` (proven on the real compiler by the
/// `MetalGateway smoke` suite). Locations still given against the assembled
/// source (`program_source:<line>:`) are rewritten as well: inside the author's
/// part to `effect:<author line>:` — the safety net should a compiler ignore the
/// directive — and inside the prelude to `prelude:<line>:`, so a note pointing
/// at a prelude declaration says so. Only a location that opens a diagnostic line
/// is rewritten: the compiler echoes the failing source line verbatim, so the
/// same text inside that excerpt or inside a message is the author's and is kept.
///
/// **The `Parameters` text is one line whatever the layout.** A struct with a line per
/// field would move every diagnostic of an effect that gains a parameter, and
/// `authorLineOffset` would depend on the manifest; with one line (a comment when there
/// are no parameters) the author's first line is at the same assembled line for every effect.
public enum ShaderSourceAssembly {
    /// The file name the author's lines are reported under.
    public static let authorFileName = "effect"
    /// The file name prelude locations are rewritten to.
    public static let preludeFileName = "prelude"

    /// The `#line` directive between the generated `Parameters` line and the author's first line.
    public static let lineDirective = "#line 1 \"\(authorFileName)\"\n"

    /// Lines of the assembled source before the author's first line: the
    /// prelude's lines, the one generated `Parameters` line and the directive's.
    /// Author line `n` is assembled line `authorLineOffset + n`.
    public static let authorLineOffset = ShaderPrelude.source.filter { $0 == "\n" }.count + 2

    /// The prelude, the `Parameters` line of `layout`, the directive and `authorSource`, in that
    /// order. `layout` defaults to no parameters, so a caller that assembles an effect without
    /// any, a test's kernel say, need not spell it out; the compile always passes its own.
    public static func assemble(_ authorSource: String, layout: EffectParameterLayout = EffectParameterLayout([])) -> String {
        ShaderPrelude.source + parametersLine(of: layout) + "\n" + lineDirective + authorSource
    }

    /// `diagnostics` with every `program_source:<line>:` location rewritten to the
    /// author's file or the prelude; the code and the cause are kept.
    public static func authorRelative(_ diagnostics: ShaderDiagnostics) -> ShaderDiagnostics {
        ShaderDiagnostics(message: authorRelative(diagnostics.message), code: diagnostics.code, cause: diagnostics.cause)
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
    /// (the generated `Parameters` line and the directive's own line included: they are
    /// the engine's text, not the author's).
    static func location(ofAssembledLine line: Int) -> String {
        line > authorLineOffset ? "\(authorFileName):\(line - authorLineOffset):" : "\(preludeFileName):\(line):"
    }

    /// The struct an author reads as `params`, field for field what `layout` places, and the
    /// `static_assert` that makes a drift between this text and the packed bytes a compile error
    /// of the effect rather than a kernel reading the wrong bytes. The comment stands in for
    /// the struct when there are no parameters, so no name is taken from an existing package.
    /// A field's id is written as it is: that it is an identifier, and so cannot end the line,
    /// is for whoever builds the specs to guarantee.
    private static func parametersLine(of layout: EffectParameterLayout) -> String {
        guard !layout.fields.isEmpty else { return "// no parameters" }
        let fields = layout.fields.map { "\($0.type.mslName) \($0.id);" }.joined(separator: " ")
        return "struct Parameters { \(fields) }; static_assert(sizeof(Parameters) == \(layout.stride), \"Parameters must mirror the manifest\");"
    }
}

extension EffectParameterFieldType {
    /// The type as MSL spells it. Written out without a default, so a new field type is a compile
    /// error here and not a struct that silently lacks it.
    fileprivate var mslName: String {
        switch self {
        case .float: "float"
        case .int: "int"
        case .uint: "uint"
        case .float2: "float2"
        case .float4: "float4"
        }
    }
}
