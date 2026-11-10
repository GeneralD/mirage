import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectPackages scaffold")
struct FakeEffectPackagesScaffoldTests {
    @Test("a scripted scaffold result is the answer, and the name and the folder of each request are kept")
    func scriptedResultIsAnswered() async {
        let packages = FakeEffectPackages()
        packages.scriptScaffold(.success("/work/A.lens"))

        let answer = await packages.scaffold(named: "A", in: "/work")

        #expect(answer == .success("/work/A.lens"))
        #expect(packages.scaffoldRequests.values == [FakeEffectPackages.ScaffoldRequest(name: "A", folder: "/work")])
    }

    @Test("a scripted scaffold failure is the answer, whatever the request")
    func scriptedFailureIsAnswered() async {
        let packages = FakeEffectPackages()
        packages.scriptScaffold(.failure(.alreadyExists(path: "/work/A.lens")))

        let answer = await packages.scaffold(named: "A", in: "/work")

        #expect(answer == .failure(.alreadyExists(path: "/work/A.lens")))
    }

    @Test("a scaffold nobody scripted is a reported issue and answers unwritable at the folder")
    func unscriptedScaffold() async {
        let packages = FakeEffectPackages()
        await withKnownIssue("a scaffold nobody scripted is reported") {
            #expect(await packages.scaffold(named: "A", in: "/work") == .failure(.unwritable(path: "/work")))
        }
    }
}
