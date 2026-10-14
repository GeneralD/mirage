import Domain
import Foundation
import TestDoubles
import TestSupport
import Testing

@Suite("FakeFileWatchGateway", .timeLimit(.minutes(1)))
struct FakeFileWatchGatewayTests {
    private struct Missing: Error, Equatable {}

    private let gateway = FakeFileWatchGateway()

    @Test("watch records the kind and the path of every watch, in order")
    func watchesAreRecorded() throws {
        _ = try gateway.watch(directory: "/effects", onChange: {})
        _ = try gateway.watch(file: "/effects/a.lens/effect.metal", onChange: {})
        #expect(
            gateway.watches.values == [
                .init(kind: .directory, path: "/effects"),
                .init(kind: .file, path: "/effects/a.lens/effect.metal"),
            ])
        #expect(gateway.watchCount == 2)
    }

    @Test("fire reaches every live watch on exactly that path, a directory watch and a file watch alike, and says how many")
    func fireReachesTheWatchersOfAPath() throws {
        let heard = Collector<String>()
        _ = try gateway.watch(directory: "/effects", onChange: { heard.append("directory") })
        _ = try gateway.watch(file: "/effects", onChange: { heard.append("file") })
        _ = try gateway.watch(file: "/effects/a.lens/effect.metal", onChange: { heard.append("other") })

        #expect(gateway.fire("/effects") == 2)
        #expect(heard.values == ["directory", "file"])
        #expect(gateway.fire("/effects/a.lens/effect.metal") == 1)
        #expect(heard.values == ["directory", "file", "other"])
        #expect(gateway.fire("/nobody/watches/this") == 0)
        #expect(heard.count == 3)
    }

    @Test("a stopped watch never fires again, and fire says nothing heard it")
    func stoppedWatchIsSilent() throws {
        let heard = Collector<Void>()
        let handle = try gateway.watch(directory: "/effects", onChange: { heard.append(()) })
        #expect(gateway.fire("/effects") == 1)

        handle.stop()
        #expect(gateway.fire("/effects") == 0)
        #expect(heard.count == 1)
        #expect(gateway.activeWatches.isEmpty)
    }

    @Test("activeWatches are the ones armed and not stopped")
    func activeWatches() throws {
        let first = try gateway.watch(directory: "/effects", onChange: {})
        _ = try gateway.watch(file: "/effects/m.json", onChange: {})
        #expect(gateway.activeWatches.count == 2)
        first.stop()
        #expect(gateway.activeWatches == [.init(kind: .file, path: "/effects/m.json")])
    }

    @Test("isBalanced: every watch stopped is balanced, one left armed is not")
    func balanceNeedsEveryStop() throws {
        #expect(gateway.isBalanced, "nothing armed, nothing to stop")
        let first = try gateway.watch(directory: "/effects", onChange: {})
        let second = try gateway.watch(file: "/effects/m.json", onChange: {})
        #expect(!gateway.isBalanced)
        first.stop()
        #expect(!gateway.isBalanced, "one watch is still armed")
        second.stop()
        #expect(gateway.isBalanced)
        #expect(gateway.stopCount == 2)
    }

    @Test("a double stop is counted, not hidden: stopCount counts the watch once and isBalanced is false")
    func doubleStop() throws {
        let handle = try gateway.watch(directory: "/effects", onChange: {})
        handle.stop()
        handle.stop()
        #expect(gateway.stopCount == 1)
        #expect(gateway.doubleStopCount == 1)
        #expect(!gateway.isBalanced, "watches armed == stops, but one of them was stopped twice")
    }

    @Test("failWatch makes arming a path throw, records nothing for it, and nil clears it")
    func failWatch() throws {
        gateway.failWatch(of: "/effects/gone", with: Missing())
        #expect(throws: Missing.self) { try gateway.watch(directory: "/effects/gone", onChange: {}) }
        #expect(throws: Missing.self) { try gateway.watch(file: "/effects/gone", onChange: {}) }
        #expect(gateway.watches.count == 0)
        #expect(gateway.isBalanced, "a watch that threw was never armed")
        _ = try gateway.watch(directory: "/effects", onChange: {})

        gateway.failWatch(of: "/effects/gone", with: nil)
        _ = try gateway.watch(directory: "/effects/gone", onChange: {})
        #expect(gateway.watchCount == 2)
    }

    @Test("a watch is armed before it is recorded, so a test that waited on `watches` can fire at once")
    func armedBeforeRecorded() async throws {
        let heard = Collector<Void>()
        let arming = Task { try gateway.watch(directory: "/effects", onChange: { heard.append(()) }) }
        await gateway.watches.waitForCount(1)
        #expect(gateway.fire("/effects") == 1)
        _ = try await arming.value
        #expect(heard.count == 1)
    }
}
