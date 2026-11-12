import TestSupport
import Testing

/// GitHub shows an issue form only when its YAML has the shape it expects, and drops a broken one without a word. These tests read each
/// form as text (the package has no YAML parser) and hold it to the parts of that shape an edit is likely to break.
@Suite("Issue forms")
struct IssueFormTests {
    private static let forms = ["bug_report", "feature_request"]
    private static let knownTypes: Set<String> = ["markdown", "textarea", "input", "dropdown", "checkboxes"]

    private struct Field {
        let type: String
        let id: String?
        let label: String?
    }

    private static func text(of form: String) throws -> String { try repositoryText(".github/ISSUE_TEMPLATE/\(form).yml") }

    /// The entries of `body:`, each starting at a line `  - type: <type>`.
    private static func fields(in text: String) -> [Field] {
        text.components(separatedBy: "\n  - type: ").dropFirst().map { chunk in
            Field(
                type: String(chunk.prefix { !$0.isNewline }),
                id: chunk.firstMatch(of: #/\n    id: ([A-Za-z0-9_-]+)/#).map { String($0.output.1) },
                label: chunk.firstMatch(of: #/\n      label: (.+)/#).map { String($0.output.1) })
        }
    }

    @Test("each form has the name, description and body that GitHub needs", arguments: forms)
    func hasTheTopLevelKeys(form: String) throws {
        let lines = try Self.text(of: form).split(separator: "\n", omittingEmptySubsequences: false)

        for key in ["name", "description", "body"] {
            #expect(lines.contains { $0.hasPrefix("\(key):") }, "\(form) has no `\(key):` key")
        }
    }

    @Test("each form has fields, and every field is of a type GitHub knows", arguments: forms)
    func fieldsAreOfKnownTypes(form: String) throws {
        let fields = Self.fields(in: try Self.text(of: form))

        #expect(!fields.isEmpty)
        #expect(fields.map(\.type).filter { !Self.knownTypes.contains($0) }.isEmpty, "unknown types in \(form): \(fields.map(\.type))")
    }

    @Test("every field that takes an answer has a label and an id, and no id is used twice", arguments: forms)
    func answersHaveIDsAndLabels(form: String) throws {
        let answers = Self.fields(in: try Self.text(of: form)).filter { $0.type != "markdown" }
        let ids = answers.compactMap(\.id)

        #expect(!answers.isEmpty)
        #expect(ids.count == answers.count, "a field of \(form) has no id")
        #expect(Set(ids).count == ids.count, "an id of \(form) is used twice: \(ids)")
        #expect(answers.allSatisfy { $0.label != nil }, "a field of \(form) has no label")
    }

    @Test("the bug form asks what happened, how to reproduce it, the app version and the macOS version")
    func bugFormAsksTheEssentials() throws {
        let ids = Set(Self.fields(in: try Self.text(of: "bug_report")).compactMap(\.id))

        #expect(ids.isSuperset(of: ["what-happened", "steps", "version", "macos"]), "the form asks only for \(ids.sorted())")
    }

    @Test("the feature form asks for the problem and for the proposal")
    func featureFormAsksTheEssentials() throws {
        let ids = Set(Self.fields(in: try Self.text(of: "feature_request")).compactMap(\.id))

        #expect(ids.isSuperset(of: ["problem", "proposal"]), "the form asks only for \(ids.sorted())")
    }

    @Test("no form names the product", arguments: forms)
    func keepsTheProductNameOut(form: String) throws {
        let name = try productName()

        #expect(!(try Self.text(of: form)).lowercased().contains(name.lowercased()))
    }
}
