import Dependencies
import Domain
import EffectPackageDataSource
import Foundation
import Presenters
import TestDoubles
import TestSupport
import Testing

@testable import LensTool

/// `docs/authoring/first-effect.md` is the tutorial an author follows from an empty folder, so each fact it states is held to the code:
/// its headings, its nine fences, the commands in its shell fences, the lines its outputs repeat, the scaffold text and the kernel it asks
/// the author to write, which the real package DataSource reads from an in-memory tree, and its links.
@Suite("First effect doc", .timeLimit(.minutes(1)))
struct FirstEffectDocTests {
    static let path = "docs/authoring/first-effect.md"

    /// The repository root, found from this file's folder three levels up, as `MarkdownFences.read` finds it.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The nine fences of the page, by their place in document order.
    enum Shown: Int {
        case newCommand, newOutput, manifest, template, kernel, validateCommand, validateOutput, renderCommand, renderOutput
    }

    /// The folder the package is read from in the in-memory tree.
    static let swapFolder = "/work/Swap.lens"

    static func document() throws -> String {
        try MarkdownFences.read(path)
    }

    static func allFences() throws -> [MarkdownFence] {
        MarkdownFences.all(in: try document())
    }

    static func fence(_ shown: Shown) throws -> MarkdownFence {
        let fences = try allFences()
        return try #require(fences.indices.contains(shown.rawValue) ? fences[shown.rawValue] : nil)
    }

    /// The fence written as the page writes its info string: the language, then each attribute as `key=value`.
    static func fenceKind(of fence: MarkdownFence) -> String {
        let attributes = fence.attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return ([fence.language] + attributes).joined(separator: " ")
    }

    /// The lines outside every fence: the headings, the links and the prose.
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

    /// The H2 heading the line `line` (1-based) falls under, or `""` before the first H2.
    static func section(atLine line: Int) throws -> String {
        let lines = try document().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.prefix(line).last(where: { $0.hasPrefix("## ") }) ?? ""
    }

    /// The package `Swap` as the page writes it: the manifest and the kernel the page shows, written into an in-memory tree and read
    /// by the real DataSource over that tree, so no disk is touched.
    static func readSwap() async throws -> EffectPackageListing? {
        let files = InMemoryFileSystemGateway()
        let manifest = try fence(.manifest).text
        let kernel = try fence(.kernel).text
        files.write("\(swapFolder)/manifest.json", manifest)
        files.write("\(swapFolder)/effect.metal", kernel)
        let subject = withDependencies {
            $0.fileSystemGateway = files
            $0.appDirectories = FixedAppDirectories(effectsDirectory: "/work/effects")
            $0.workspaceGateway = FakeWorkspaceGateway()
            $0.errorLog = RecordingLog()
            $0.developerLog = RecordingLog()
        } operation: {
            EffectPackageDataSourceImpl()
        }
        return await subject.package(atPath: swapFolder)
    }

    // MARK: Structure

    @Test("the page has one H1, `# Your first effect`, then the eight H2s in order, and no other heading")
    func headingsAreInOrder() throws {
        let headings = try Self.prose().filter { $0.hasPrefix("#") }
        #expect(
            headings == [
                "# Your first effect",
                "## Before you start",
                "## 1. Create the package",
                "## 2. Look inside",
                "## 3. Make it yours",
                "## 4. Check it",
                "## 5. See it on a picture",
                "## 6. Use it in the app",
                "## Where to go next",
            ])
    }

    @Test("the page shows nine fences in this order: sh, text, json, metal, metal, sh, text, sh, text")
    func fencesAreInOrder() throws {
        let kinds = try Self.allFences().map(Self.fenceKind(of:))
        #expect(
            kinds == [
                "sh",
                "text",
                "json scaffold=manifest",
                "metal scaffold=effect",
                "metal result=effect",
                "sh",
                "text",
                "sh",
                "text",
            ])
    }

    @Test(
        "each fence sits under the step it belongs to: the new command and its output under 1, the manifest and the template under 2, the kernel under 3, the check under 4 and the render under 5"
    )
    func fencesSitUnderTheirSteps() throws {
        let expected: [(Shown, String)] = [
            (.newCommand, "## 1. Create the package"),
            (.newOutput, "## 1. Create the package"),
            (.manifest, "## 2. Look inside"),
            (.template, "## 2. Look inside"),
            (.kernel, "## 3. Make it yours"),
            (.validateCommand, "## 4. Check it"),
            (.validateOutput, "## 4. Check it"),
            (.renderCommand, "## 5. See it on a picture"),
            (.renderOutput, "## 5. See it on a picture"),
        ]
        for (shown, heading) in expected {
            let fence = try Self.fence(shown)
            let actual = try Self.section(atLine: fence.line)
            #expect(actual == heading, "\(shown) is under \(actual)")
        }
    }

    // MARK: Commands and outputs

    @Test("every sh fence is a `swift run lens-tool` command, and the arguments after it parse to the command its step runs")
    func shellFencesParseToTheirCommands() throws {
        let prefix = "swift run lens-tool "
        let expected: [(Shown, LensCommand)] = [
            (.newCommand, .scaffold(name: "Swap", folder: "/tmp/lenses")),
            (.validateCommand, .validate(path: "/tmp/lenses/Swap.lens")),
            (.renderCommand, .render(effect: .package(path: "/tmp/lenses/Swap.lens"), input: "photo.png", output: "swapped.png")),
        ]
        for (shown, command) in expected {
            let line = try Self.fence(shown).text.trimmingCharacters(in: .newlines)
            #expect(line.hasPrefix(prefix), "\(line)")
            let arguments = line.dropFirst(prefix.count).split(separator: " ").map(String.init)
            #expect(LensToolArguments.parse(arguments) == .success(command), "\(line)")
        }
    }

    @Test("each text fence is the line the tool prints for its command, followed by a newline")
    func textFencesAreThePrintedLines() async throws {
        let listing = try await Self.readSwap()
        guard case .ready(let package)? = listing else {
            Issue.record("Swap is not ready: \(String(describing: listing))")
            return
        }
        let newOutput = try Self.fence(.newOutput).text
        let validateOutput = try Self.fence(.validateOutput).text
        let renderOutput = try Self.fence(.renderOutput).text
        #expect(newOutput == AuthoringReportText.scaffolded(path: "/tmp/lenses/Swap.lens") + "\n")
        #expect(validateOutput == AuthoringReportText.validated(package.source) + "\n")
        #expect(
            renderOutput
                == AuthoringReportText.rendered(
                    effect: .package(path: "/tmp/lenses/Swap.lens"), output: "swapped.png", size: StillImageSize(width: 1280, height: 720))
                + "\n")
    }

    // MARK: Scaffold and kernel

    @Test("the manifest and the kernel template the page shows are the text the scaffold command writes")
    func scaffoldFencesAreTheTemplate() throws {
        let manifest = try Self.fence(.manifest).text
        let template = try Self.fence(.template).text
        #expect(manifest == EffectScaffoldTemplate.manifest(named: "Swap"))
        #expect(template == EffectScaffoldTemplate.effectSource)
    }

    @Test("the kernel the author writes defines `effect` once, reads `params.strength`, declares no struct and no include, and is not the template")
    func swapKernelIsAnEffectKernel() throws {
        let kernel = try Self.fence(.kernel).text
        let template = try Self.fence(.template).text
        #expect(kernel.components(separatedBy: "kernel void effect(").count - 1 == 1)
        #expect(kernel.contains("params.strength"))
        #expect(!kernel.contains("struct Parameters"))
        #expect(!kernel.contains("struct Uniforms"))
        #expect(!kernel.contains("#include"))
        #expect(kernel != template)
    }

    @Test("the package the page builds reads as ready: named Swap, with one parameter `strength`, and the kernel the page shows")
    func swapPackageIsReady() async throws {
        let listing = try await Self.readSwap()
        guard case .ready(let package)? = listing else {
            Issue.record("Swap is not ready: \(String(describing: listing))")
            return
        }
        let kernel = try Self.fence(.kernel).text
        #expect(package.manifest.name == "Swap")
        #expect(package.source.parameters.map(\.id) == ["strength"])
        #expect(package.source.source == kernel)
    }

    // MARK: Links and naming

    @Test("the page has three or more relative links, and each reaches a file that exists from the page's folder")
    func linksReachExistingFiles() throws {
        let targets = try Self.prose().flatMap { (line: String) -> [String] in
            line.components(separatedBy: "](").dropFirst().map { part in String(part.prefix { $0 != ")" }) }
        }
        let relative = targets.filter { !$0.hasPrefix("http") && !$0.hasPrefix("#") }
        let folder = Self.root.appending(path: "docs/authoring", directoryHint: .isDirectory)
        #expect(relative.count >= 3)
        for target in relative {
            let file = URL(fileURLWithPath: String(target.prefix { $0 != "#" }), relativeTo: folder).standardizedFileURL
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
