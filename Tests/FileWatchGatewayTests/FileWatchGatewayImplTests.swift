import Foundation
import TestSupport
import Testing

@testable import FileWatchGateway

/// Smoke of the live gateway against real kernel file events, under a UUID-named temporary
/// directory that each test removes. The OS coalesces events, so every assertion is "at least
/// one"; it never counts how many arrived (coalescing is `EffectWatchDataSource`'s, under a
/// `TestClock`). Waits are on the callback itself (`Collector`), bounded by the suite's limit.
@Suite("FileWatchGatewayImpl", .timeLimit(.minutes(1)))
struct FileWatchGatewayImplTests {
    private let gateway = FileWatchGatewayImpl()

    @Test("an atomic write into a watched directory is reported")
    func directoryReportsAtomicWrite() async throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let fired = Collector<Void>()
        let handle = try gateway.watch(directory: scratch.path) { fired.append(()) }
        defer { handle.stop() }

        try "hello".write(toFile: scratch.appending("effect.metal"), atomically: true, encoding: .utf8)

        await fired.waitForCount(1)
        #expect(fired.count >= 1)
    }

    @Test("an in-place overwrite of a watched file is reported")
    func fileReportsInPlaceWrite() async throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = scratch.appending("effect.metal")
        try "hello".write(toFile: file, atomically: true, encoding: .utf8)
        let fired = Collector<Void>()
        let handle = try gateway.watch(file: file) { fired.append(()) }
        defer { handle.stop() }

        // No rename here, so a directory watch would never see it: the editor-save style the file watch is for.
        try append(" world", to: file)

        await fired.waitForCount(1)
        #expect(fired.count >= 1)
    }

    @Test("a truncate that only shrinks a watched file (an attribute event, no write) is reported")
    func fileReportsShrinkingTruncate() async throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = scratch.appending("effect.metal")
        try "hello world".write(toFile: file, atomically: true, encoding: .utf8)
        let fired = Collector<Void>()
        let handle = try gateway.watch(file: file) { fired.append(()) }
        defer { handle.stop() }

        let writer = try FileHandle(forWritingTo: URL(fileURLWithPath: file))
        defer { try? writer.close() }
        try writer.truncate(atOffset: 5)

        await fired.waitForCount(1)
        #expect(fired.count >= 1)
    }

    @Test("a directory watch stays silent for an in-place write to a file inside it; the file watch hears it")
    func directoryDoesNotHearInPlaceWrites() async throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = scratch.appending("effect.metal")
        try "hello".write(toFile: file, atomically: true, encoding: .utf8)
        let directoryEvents = Collector<Void>()
        let fileEvents = Collector<Void>()
        let directoryWatch = try gateway.watch(directory: scratch.path) { directoryEvents.append(()) }
        defer { directoryWatch.stop() }
        let fileWatch = try gateway.watch(file: file) { fileEvents.append(()) }
        defer { fileWatch.stop() }

        try append(" world", to: file)

        // The file watch is the sentinel: once it has reported the write, the directory watch had every chance to.
        await fileEvents.waitForCount(1)
        #expect(directoryEvents.count == 0)
    }

    @Test("after stop() a watch reports nothing: only the watch that is still armed does")
    func stopSilencesTheWatch() async throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let stoppedEvents = Collector<Void>()
        let sentinelEvents = Collector<Void>()
        let stopped = try gateway.watch(directory: scratch.path) { stoppedEvents.append(()) }
        let sentinel = try gateway.watch(directory: scratch.path) { sentinelEvents.append(()) }
        defer { sentinel.stop() }

        stopped.stop()
        try await provokeEvent(into: sentinelEvents, in: scratch, as: "one")
        try await provokeEvent(into: sentinelEvents, in: scratch, as: "two")

        #expect(stoppedEvents.count == 0)
    }

    @Test("a path that does not exist cannot be watched, as a directory or as a file")
    func missingPathThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        #expect(throws: (any Error).self) { try gateway.watch(directory: scratch.appending("missing")) {} }
        #expect(throws: (any Error).self) { try gateway.watch(file: scratch.appending("missing")) {} }
    }

    // MARK: helpers

    private func append(_ text: String, to path: String) throws {
        let writer = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? writer.close() }
        try writer.seekToEnd()
        try writer.write(contentsOf: Data(text.utf8))
    }

    /// Writes a new file into `scratch` and waits until `events` has reported one more event than it had.
    private func provokeEvent(into events: Collector<Void>, in scratch: ScratchDirectory, as name: String) async throws {
        let before = events.count
        try "hello".write(toFile: scratch.appending(name), atomically: true, encoding: .utf8)
        await events.settle { $0.count > before }
    }
}
