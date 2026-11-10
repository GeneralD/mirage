import Dependencies
import Domain
import TestDoubles
import Testing

@testable import PreferencesDataStore

@Suite("PreferencesDataStoreImpl parameters", .timeLimit(.minutes(1)))
struct PreferencesDataStoreParameterTests {
    private let glitch = EffectID.package("glitch")
    private let chromatic = EffectID.bundled("Chromatic Grain")
    /// The persisted key of `glitch`'s values, written out by hand: a change to it changes what an
    /// installed build reads back, so the tests compare against this exact string.
    private let glitchKey = "effect.parameters.v1.package:glitch"

    private func makeSubject(_ store: InMemoryKeyValueStore, log: RecordingLog = RecordingLog()) -> PreferencesDataStoreImpl {
        withDependencies {
            $0.keyValueStoreGateway = store
            $0.developerLog = log
        } operation: {
            PreferencesDataStoreImpl()
        }
    }

    @Test("the values of an effect are kept under effect.parameters.v1. followed by the effect's encoded id")
    func persistedKey() {
        #expect(StoredParameterValues.key(of: glitch) == "effect.parameters.v1.package:glitch")
        #expect(StoredParameterValues.key(of: chromatic) == "effect.parameters.v1.bundled:Chromatic Grain")
    }

    @Test("the values of one effect are stored as one JSON object under its key, with the keys sorted")
    func storedForm() async {
        let store = InMemoryKeyValueStore()
        await makeSubject(store).setParameterValues(["strength": .float(0.5), "inverted": .bool(false)], of: glitch)
        #expect(store.values == [glitchKey: #"{"inverted":{"bool":{"_0":false}},"strength":{"float":{"_0":0.5}}}"#])
        #expect(store.writes.values == [glitchKey])
    }

    @Test("the parameter values are set and read through the Preferences protocol, not only the concrete type")
    func protocolRoundTrip() async {
        let subject: any Preferences = makeSubject(InMemoryKeyValueStore())
        await subject.setParameterValues(["strength": .float(0.5)], of: glitch)
        #expect(await subject.parameterValues(of: glitch) == ["strength": .float(0.5)])
    }

    @Test("a value in the persisted form reads back as the values it holds, and reading writes nothing")
    func readsStoredForm() async {
        let store = InMemoryKeyValueStore([glitchKey: #"{"strength":{"float":{"_0":0.5}}}"#])
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).parameterValues(of: glitch) == ["strength": .float(0.5)])
        #expect(log.entries.count == 0)
        #expect(store.writes.count == 0, "reading writes nothing")
    }

    @Test("the six kinds of value come back as they were set, through a new subject over the same store, as after a relaunch")
    func sixKindsRoundTrip() async {
        let store = InMemoryKeyValueStore()
        let values: [String: EffectParameterValue] = [
            "strength": .float(0.25),
            "rings": .int(-3),
            "inverted": .bool(true),
            "tint": .color(SIMD4<Float>(0.5, 0.25, 0.75, 1)),
            "offset": .vector2(SIMD2<Float>(0.5, -0.25)),
            "mode": .choice(2),
        ]
        await makeSubject(store).setParameterValues(values, of: glitch)
        #expect(await makeSubject(store).parameterValues(of: glitch) == values)
    }

    @Test("two effects keep their values apart: a write to one leaves the values of the other as they were")
    func effectsStayApart() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        await subject.setParameterValues(["strength": .float(0.5)], of: glitch)
        await subject.setParameterValues(["mode": .choice(1)], of: chromatic)
        #expect(await subject.parameterValues(of: glitch) == ["strength": .float(0.5)])
        #expect(await subject.parameterValues(of: chromatic) == ["mode": .choice(1)])
        #expect(store.values.count == 2)
    }

    @Test("a second write to the same effect replaces the values under the same key")
    func secondWriteReplaces() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        await subject.setParameterValues(["strength": .float(0.5)], of: glitch)
        await subject.setParameterValues(["rings": .int(9)], of: glitch)
        #expect(store.values == [glitchKey: #"{"rings":{"int":{"_0":9}}}"#])
        #expect(await subject.parameterValues(of: glitch) == ["rings": .int(9)])
        #expect(store.writes.values == [glitchKey, glitchKey])
    }

    @Test("an empty dictionary is stored as {} and reads back as an empty dictionary, with nothing logged")
    func emptyDictionary() async {
        let store = InMemoryKeyValueStore([glitchKey: #"{"strength":{"float":{"_0":0.5}}}"#])
        let log = RecordingLog()
        let subject = makeSubject(store, log: log)
        await subject.setParameterValues([:], of: glitch)
        #expect(store.values == [glitchKey: "{}"])
        #expect(await subject.parameterValues(of: glitch) == [:])
        #expect(log.entries.count == 0)
    }

    @Test("nothing stored reads as an empty dictionary, with nothing written and nothing logged")
    func nothingStored() async {
        let store = InMemoryKeyValueStore()
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).parameterValues(of: glitch) == [:])
        #expect(store.writes.count == 0)
        #expect(log.entries.count == 0)
    }

    @Test(
        "a stored value that does not decode reads as an empty dictionary, logs one line, and is left where it is",
        arguments: ["", "garbage", "[]", #"{"a":1}"#, #"{"a":{"nope":{}}}"#])
    func malformed(stored: String) async {
        let store = InMemoryKeyValueStore([glitchKey: stored])
        let log = RecordingLog()
        let subject = makeSubject(store, log: log)
        #expect(await subject.parameterValues(of: glitch) == [:])
        #expect(log.entries.values == [LogEntry(.effect, "stored parameter values of 'package:glitch' do not decode, ignored: \(stored)")])
        #expect(store.values == [glitchKey: stored], "another build may have written it, and may read it again")
        #expect(store.writes.count == 0)
    }

    @Test(
        "a value that does not encode is not stored, logs one line, and leaves the values already stored as they were",
        arguments: [Float.nan, Float.infinity])
    func unencodable(value: Float) async {
        let stored = #"{"strength":{"float":{"_0":0.5}}}"#
        let store = InMemoryKeyValueStore([glitchKey: stored])
        let log = RecordingLog()
        await makeSubject(store, log: log).setParameterValues(["strength": .float(value)], of: glitch)
        #expect(store.writes.count == 0)
        #expect(store.values == [glitchKey: stored])
        #expect(log.entries.values == [LogEntry(.effect, "parameter values of 'package:glitch' do not encode, not stored")])
    }
}
