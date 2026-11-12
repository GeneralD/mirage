import Foundation
import TestSupport
import Testing

/// Release notes come from the tags the Auto Tag workflow pushes, with no signing: the workflow cannot be run from a test, so these
/// tests hold its text to the parts that make it work and keep a signing secret out of it.
@Suite("Release notes wiring")
struct ReleaseNotesWiringTests {
    private static let workflow = ".github/workflows/auto-tag.yml"

    @Test("the workflow creates a release for the tag, verified to exist, with notes generated from the pull requests")
    func createsAGeneratedRelease() throws {
        let text = try repositoryText(Self.workflow)

        for phrase in ["gh release create \"$TAG\"", "--verify-tag", "--generate-notes"] {
            #expect(text.contains(phrase), "the workflow lacks: \(phrase)")
        }
    }

    @Test("the notes start at the previous tag that the new tag contains, and the checkout has the whole history and every tag")
    func notesStartAtThePreviousTag() throws {
        let text = try repositoryText(Self.workflow)

        for phrase in ["git tag --merged \"$TAG\"", "--notes-start-tag \"$PREVIOUS\"", "fetch-depth: 0", "fetch-tags: true"] {
            #expect(text.contains(phrase), "the workflow lacks: \(phrase)")
        }
    }

    @Test("the release is created after the tag is pushed")
    func releaseFollowsTheTag() throws {
        let text = try repositoryText(Self.workflow)
        let push = try #require(text.range(of: "git push origin \"$TAG\""))
        let create = try #require(text.range(of: "gh release create"))

        #expect(push.lowerBound < create.lowerBound)
    }

    @Test("between the push and the release, the step waits a bounded number of times for the API to see the tag")
    func releaseWaitsForThePushedTag() throws {
        let text = try repositoryText(Self.workflow)
        let push = try #require(text.range(of: "git push origin \"$TAG\""))
        let create = try #require(text.range(of: "gh release create"))
        try #require(push.upperBound <= create.lowerBound)
        let between = text[push.upperBound..<create.lowerBound]

        for phrase in ["for i in $(seq 1 ", "gh api \"repos/${REPO}/git/refs/tags/${TAG}\"", "&& break", "sleep "] {
            #expect(between.contains(phrase), "the wait lacks: \(phrase)")
        }
    }

    @Test("the step that creates the release has the token and the repository in its environment")
    func releaseStepHasItsEnvironment() throws {
        let text = try repositoryText(Self.workflow)
        let step = try #require(text.range(of: "name: Create release with generated notes if missing"))
        let tail = text[step.upperBound...]

        #expect(tail.contains("GH_TOKEN:"))
        #expect(tail.contains("REPO:"))
    }

    @Test("a release that already exists is left alone, so a re-run creates nothing twice")
    func skipsAnExistingRelease() throws {
        #expect(try repositoryText(Self.workflow).contains("gh release view \"$TAG\""))
    }

    @Test("the workflow may write contents and uses no secret and no signing tool")
    func needsNoSigning() throws {
        let text = try repositoryText(Self.workflow)
        let code = text.split(separator: "\n").filter { !$0.drop { $0 == " " }.hasPrefix("#") }.joined(separator: "\n")

        #expect(code.contains("contents: write"))
        for forbidden in ["secrets.", "codesign", "notarytool", "security import", "Developer ID"] {
            #expect(!code.contains(forbidden), "the workflow mentions \(forbidden) outside a comment")
        }
    }
}
