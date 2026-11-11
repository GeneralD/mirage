import Domain
import EffectPackageDataSource
import Foundation
import TestSupport
import Testing

/// `docs/authoring/parameters.md` is what an author writes a parameter from, so each fact it states is held to the code: its
/// headings, its fences, its table and its links, and the manifests and layouts it shows, which the reader and the layout decide.
/// A fence that shows a file is that file byte for byte, so the page cannot drift from the examples it cites.
@Suite("Parameter doc", .timeLimit(.minutes(1)))
struct ParametersDocTests {
    static let path = "docs/authoring/parameters.md"

    /// The repository root, found from this file's folder three levels up, as `MarkdownFences.read` finds it.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func document() throws -> String {
        try MarkdownFences.read(path)
    }

    static func allFences() throws -> [MarkdownFence] {
        MarkdownFences.all(in: try document())
    }

    /// The fence whose kind is `kind`, written as the page writes its info string: the language, then each attribute as `key=value`.
    static func fence(_ kind: String) throws -> MarkdownFence {
        let fences = try allFences()
        return try #require(fences.first { fenceKind(of: $0) == kind })
    }

    static func fenceKind(of fence: MarkdownFence) -> String {
        let attributes = fence.attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return ([fence.language] + attributes).joined(separator: " ")
    }

    /// The lines outside every fence: the headings, the table and the prose.
    static func prose() throws -> [String] {
        let lines = try document().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.reduce(into: (kept: [String](), inFence: false)) { state, line in
            if line.hasPrefix("```") {
                state.inFence.toggle()
            } else if !state.inFence {
                state.kept.append(line)
            }
        }.kept
    }

    /// The prose under the H2 `title`, up to the next H2.
    static func section(_ title: String) throws -> String {
        let lines = try prose()
        guard let start = lines.firstIndex(of: "## \(title)") else { return "" }
        return lines[(start + 1)...].prefix { !$0.hasPrefix("## ") }.joined(separator: "\n")
    }

    /// The layout of the Parameter Tour, read from its manifest through the reader the app uses.
    static func tourLayout() throws -> EffectParameterLayout {
        let manifest = try EffectManifestDecoding.decode(fence("json file=Examples/ParameterTour.lens/manifest.json").text).get()
        return EffectParameterLayout(manifest.parameters)
    }

    /// The name the page gives a parameter's kind, which is the `type` an author writes.
    static func typeName(of kind: EffectParameterKind) -> String {
        switch kind {
        case .float: "float"
        case .int: "int"
        case .bool: "bool"
        case .color: "color"
        case .vector2: "vec2"
        case .choice: "choice"
        }
    }

    // MARK: Structure

    @Test("the page has one H1, `# Effect parameters`, then the five H2s in order, and no other heading")
    func headingsAreInOrder() throws {
        let headings = try Self.prose().filter { $0.hasPrefix("#") }
        #expect(
            headings == [
                "# Effect parameters",
                "## Declaring parameters",
                "## The six kinds",
                "## What the reader rejects",
                "## What the kernel sees",
                "## Try it",
            ])
    }

    @Test("the page shows eight fences in this order: two manifests, a layout, a struct, three rejected manifests and a kernel")
    func fencesAreInOrder() throws {
        let kinds = try Self.allFences().map(Self.fenceKind(of:))
        #expect(
            kinds == [
                "json file=Examples/Tint.lens/manifest.json",
                "json file=Examples/ParameterTour.lens/manifest.json",
                "text layout=Examples/ParameterTour.lens",
                "metal struct=Examples/ParameterTour.lens",
                "json invalid=parameters[0].default",
                "json invalid=parameters[1].id",
                "json invalid=parameters[0].type",
                "metal file=Examples/Tint.lens/effect.metal",
            ])
    }

    @Test("every fence with a `file=` is the file it names, byte for byte")
    func fileFencesShowTheirFiles() throws {
        let fences = try Self.allFences().filter { $0.attributes["file"] != nil }
        #expect(fences.count == 3)
        for fence in fences {
            let filePath = try #require(fence.attributes["file"])
            let file = try MarkdownFences.read(filePath)
            #expect(fence.text == file, "\(filePath) differs from its fence")
        }
    }

    // MARK: Declaring parameters

    @Test("the declaring section gives the limits the reader enforces: 32 parameters at most, the identifier pattern and formatVersion")
    func declaringStatesItsLimits() throws {
        let text = try Self.section("Declaring parameters")
        #expect(text.contains("32"))
        #expect(text.contains("^[A-Za-z_][A-Za-z0-9_]{0,63}$"))
        #expect(text.contains("`formatVersion`"))
    }

    @Test("the Tint manifest and the Parameter Tour manifest read as packages, and the Tour's six parameters are of the six kinds in order")
    func manifestsRead() throws {
        let tint = try EffectManifestDecoding.decode(Self.fence("json file=Examples/Tint.lens/manifest.json").text).get()
        let tour = try EffectManifestDecoding.decode(Self.fence("json file=Examples/ParameterTour.lens/manifest.json").text).get()
        #expect(tint.name == "Tint")
        #expect(tint.parameters.map(\.id) == ["tint", "amount"])
        #expect(tour.name == "Parameter Tour")
        #expect(tour.parameters.map(\.id) == ["strength", "reach", "inverted", "tint", "center", "mode"])
        #expect(tour.parameters.map { Self.typeName(of: $0.kind) } == ["float", "int", "bool", "color", "vec2", "choice"])
    }

    // MARK: The six kinds

    @Test("the six kinds table has one row per type name, and the rows are in the order `typeNames` lists them")
    func kindsTableFollowsTypeNames() throws {
        let rows = try Self.prose().filter { $0.hasPrefix("| `") }
        let names = EffectParameterSpec.typeNames
        #expect(rows.count == names.count)
        for (row, name) in zip(rows, names) {
            #expect(row.hasPrefix("| `\(name)` |"), "\(row)")
        }
    }

    @Test("the layout the page shows is the Parameter Tour's: each field with its type and offset, then the size, 48 bytes")
    func layoutFenceIsTheLayout() throws {
        let layout = try Self.tourLayout()
        let lines = layout.fields.map { "\($0.id) \(String(describing: $0.type)) offset \($0.offset)" } + ["size \(layout.stride)"]
        let shown = try Self.fence("text layout=Examples/ParameterTour.lens")
        #expect(shown.text == lines.map { $0 + "\n" }.joined())
        #expect(layout.stride == 48)
    }

    @Test("the struct line the page shows is the line the app writes for the Parameter Tour's layout, sized to its stride")
    func structFenceIsTheGeneratedLine() throws {
        let layout = try Self.tourLayout()
        let fields = layout.fields.map { "\(String(describing: $0.type)) \($0.id);" }.joined(separator: " ")
        let line =
            "struct Parameters { \(fields) }; static_assert(sizeof(Parameters) == \(layout.stride), \"Parameters must mirror the manifest\");"
        let shown = try Self.fence("metal struct=Examples/ParameterTour.lens")
        #expect(shown.text == line + "\n")
    }

    // MARK: What the reader rejects

    @Test("the rejection section names the key at fault by its position, as `parameters[2].default`")
    func rejectionSectionNamesTheKey() throws {
        let text = try Self.section("What the reader rejects")
        #expect(text.contains("`parameters[2].default`"))
    }

    @Test("each rejected manifest is refused for the one rule its fence names, with the message that names that key")
    func rejectedManifestsAreRefused() throws {
        let rejected: [(kind: String, message: String)] = [
            ("json invalid=parameters[0].default", "\"parameters[0].default\" is outside \"min\" to \"max\""),
            ("json invalid=parameters[1].id", "\"parameters[1].id\" repeats \"parameters[0].id\""),
            ("json invalid=parameters[0].type", "\"parameters[0].type\" is not one of float, int, bool, color, vec2, choice"),
        ]
        for (kind, message) in rejected {
            let fence = try Self.fence(kind)
            #expect(EffectManifestDecoding.decode(fence.text) == .failure(.manifestInvalid(message: message)), "\(kind)")
        }
    }

    // MARK: What the kernel sees

    @Test("the kernel section tells the author to add the Parameters argument at buffer 1 and to read a field as `params.strength`")
    func kernelSectionShowsTheArgument() throws {
        let text = try Self.section("What the kernel sees")
        #expect(text.contains("constant Parameters &params [[buffer(1)]]"))
        #expect(text.contains("`params.strength`"))
    }

    @Test("the kernel the page shows reads `params` at buffer 1 and declares no `Parameters` struct of its own")
    func kernelReadsParamsAtBufferOne() throws {
        let kernel = try Self.fence("metal file=Examples/Tint.lens/effect.metal").text
        #expect(kernel.contains("constant Parameters &params [[buffer(1)]]"))
        #expect(!kernel.contains("struct Parameters"))
    }

    // MARK: Try it, links and naming

    @Test("the try-it section names `lens-tool validate <package>`")
    func tryItNamesTheValidateCommand() throws {
        let text = try Self.section("Try it")
        #expect(text.contains("`lens-tool validate <package>`"))
    }

    @Test("the page links to two example packages, and each link reaches a file that exists from the page's folder")
    func linksReachExistingFiles() throws {
        let targets = try Self.prose().flatMap { (line: String) -> [String] in
            line.components(separatedBy: "](").dropFirst().map { part in String(part.prefix { $0 != ")" }) }
        }
        let folder = Self.root.appending(path: "docs/authoring", directoryHint: .isDirectory)
        #expect(targets.count >= 2)
        let documents = targets.filter { $0.hasSuffix(".md") }
        #expect(documents.isEmpty, "the page links to another document: \(documents)")
        for target in targets {
            let file = URL(fileURLWithPath: target, relativeTo: folder).standardizedFileURL
            #expect(FileManager.default.fileExists(atPath: file.path), "\(target) does not exist")
        }
    }

    @Test("the page names the app, never the product, and does not mention Application Support")
    func pageNamesNoProductOrSupportFolder() throws {
        let text = try Self.document()
        #expect(!text.localizedCaseInsensitiveContains(ProductIdentity.displayName))
        #expect(!text.contains("Application Support"))
    }
}
