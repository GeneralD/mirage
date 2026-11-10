import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectPackages paths")
struct FakeEffectPackagesPathTests {
    private let glitch = EffectPackage.fixture(.package("glitch"))

    @Test("package(atPath:) answers the listing scripted for that path, and records the path it was asked for")
    func scriptedPathIsAnswered() async {
        let packages = FakeEffectPackages()
        packages.script(.ready(glitch), atPath: "/work/Glitch.lens")

        #expect(await packages.package(atPath: "/work/Glitch.lens") == .ready(glitch))
        #expect(packages.pathRequests.values == ["/work/Glitch.lens"])
    }

    @Test("package(atPath:) answers nil for a path nothing was scripted for, and still records that path")
    func unscriptedPathIsNil() async {
        let packages = FakeEffectPackages()
        packages.script(.ready(glitch), atPath: "/work/Glitch.lens")

        #expect(await packages.package(atPath: "/work/other.lens") == nil)
        #expect(packages.pathRequests.values == ["/work/other.lens"])
    }

    @Test("a nil script takes the listing away for its own path only")
    func nilTakesTheScriptAway() async {
        let packages = FakeEffectPackages()
        packages.script(.ready(glitch), atPath: "/work/Glitch.lens")
        packages.script(.broken(.package("blur"), .sourceMissing), atPath: "/work/Blur.lens")
        packages.script(nil, atPath: "/work/Glitch.lens")

        #expect(await packages.package(atPath: "/work/Glitch.lens") == nil)
        #expect(await packages.package(atPath: "/work/Blur.lens") == .broken(.package("blur"), .sourceMissing))
    }
}
