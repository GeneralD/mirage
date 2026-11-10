import Foundation
import Testing

@testable import ViewGallery

private final class Marker {}

private func screen(_ name: String, _ summary: String = "A screen") -> GalleryScreen {
    GalleryScreen(name: name, summary: summary) { Marker() }
}

/// What is wrong with a registry, one sentence each. A name collision between two screens added by parallel changes is the case
/// `merge=union` cannot see, so this is where it turns red.
private func problems(in screens: [GalleryScreen]) -> [String] {
    let names = screens.map(\.name)
    let duplicates = Set(names.filter { name in names.filter { $0 == name }.count > 1 }).sorted()
    let badNames = names.filter { $0.range(of: "^[a-z][a-z0-9]*(-[a-z0-9]+)*$", options: .regularExpression) == nil }
    let badSummaries = screens.filter { $0.summary.isEmpty || $0.summary.contains("\n") || $0.summary.contains("\t") }.map(\.name)
    return duplicates.map { "duplicate name \($0)" } + badNames.map { "bad name \($0)" } + badSummaries.map { "bad summary of \($0)" }
}

@Suite("GalleryScreens")
struct GalleryScreensTests {
    @Test("two screens with one name are reported")
    func duplicateNames() {
        #expect(problems(in: [screen("a"), screen("b"), screen("a")]) == ["duplicate name a"])
    }

    @Test(
        "a name that is not lowercase ASCII words joined by hyphens is reported",
        arguments: ["Effect_Picker", "effect picker", "-x", "x-", "1x", "a--b", ""])
    func badNames(name: String) {
        #expect(problems(in: [screen(name)]) == ["bad name \(name)"])
    }

    @Test("a summary that is empty, or holds a newline or a tab, is reported", arguments: ["", "two\nlines", "tab\there"])
    func badSummaries(summary: String) {
        #expect(problems(in: [screen("ok", summary)]) == ["bad summary of ok"])
    }

    @Test("the registry has none of those problems")
    func registryIsSound() {
        #expect(problems(in: galleryScreens).isEmpty)
    }
}
