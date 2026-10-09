import Domain
import TestDoubles
import TestSupport
import Testing

/// The fakes count clients like `StreamOutputDataSourceImpl`: streaming while at
/// least one client is connected, events only on the 0 to 1 and 1 to 0 edges.
@Suite struct FakeStreamOutputClientTests {
    private let handle = FakeSurfaceHandle(id: 1)

    @Test func outputEmitsOnlyOnTheEdges() throws {
        let output = FakeStreamOutput()
        let events = Collector<StreamOutputEvent>()
        try output.start(descriptor: .hd720, frameRate: .standard, onEvent: { events.append($0) })
        output.connectClient()
        output.connectClient()
        #expect(output.isStreaming)
        output.disconnectClient()
        #expect(output.isStreaming)
        output.disconnectClient()
        #expect(!output.isStreaming)
        output.disconnectClient()
        #expect(events.values == [.streamStarted, .streamStopped])
        #expect(!output.isStreaming)
    }

    @Test func outputDropsFramesWithoutAClientAndRecordsThemWithOne() {
        let output = FakeStreamOutput()
        #expect(output.send(handle, descriptor: .hd720, presentationTime: .zero) == .dropped(.noClient))
        output.connectClient()
        #expect(output.send(handle, descriptor: .hd720, presentationTime: .zero) == .sent)
        #expect(output.sent.count == 1)
    }

    @Test func repositoryEmitsOnlyOnTheEdges() throws {
        let repository = FakeStreamOutputRepository()
        let events = Collector<StreamOutputEvent>()
        try repository.start(descriptor: .hd720, frameRate: .standard, onEvent: { events.append($0) })
        repository.connectClient()
        repository.connectClient()
        repository.disconnectClient()
        #expect(repository.isStreaming)
        repository.disconnectClient()
        repository.disconnectClient()
        #expect(events.values == [.streamStarted, .streamStopped])
        #expect(!repository.isStreaming)
    }

    @Test func setStreamingStillForcesTheState() throws {
        let repository = FakeStreamOutputRepository()
        let events = Collector<StreamOutputEvent>()
        try repository.start(descriptor: .hd720, frameRate: .standard, onEvent: { events.append($0) })
        repository.setStreaming(true)
        #expect(repository.isStreaming)
        repository.setStreaming(false)
        #expect(!repository.isStreaming)
        #expect(events.values == [.streamStarted, .streamStopped])
    }

    @Test func seedsRangeListsTheRequestedSeeds() {
        #expect(Seeds.range(0..<4) == [0, 1, 2, 3])
        #expect(Seeds.range(5..<5).isEmpty)
    }
}
