import Entity
import Foundation
import TestSupport
import Testing

private let stamp = EffectFingerprint(value: "321518f1bfcf7e49")
private let timing = GPUTiming(gpuStart: 1, gpuEnd: 1.25)

private func encoded<Value: Encodable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
    try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
}

@Suite("EffectFailureKind")
struct EffectFailureKindTests {
    @Test("the persisted form of a failure kind is its raw value, so a case is never renamed")
    func rawValues() {
        #expect(EffectFailureKind.allCases.map(\.rawValue) == ["timeout", "pageFault", "accessRevoked", "outOfMemory", "unknown"])
    }

    @Test("a kind survives encode and decode", arguments: EffectFailureKind.allCases)
    func codableRoundTrip(kind: EffectFailureKind) throws {
        #expect(try roundTrip(kind) == kind)
    }

    @Test("a raw value this build does not know does not decode")
    func unknownRawValueIsRejected() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(EffectFailureKind.self, from: Data(#""overheated""#.utf8)) }
    }
}

@Suite("EffectDisableReason")
struct EffectDisableReasonTests {
    private static let reasons: [EffectDisableReason] = EffectFailureKind.allCases.map { .failure($0) } + [.overBudget]

    @Test("a reason survives encode and decode, whichever failure kind it names", arguments: reasons)
    func codableRoundTrip(reason: EffectDisableReason) throws {
        #expect(try roundTrip(reason) == reason)
    }

    @Test("a failure and the budget are different reasons, and so are two failure kinds")
    func reasonsAreDistinct() {
        #expect(Set(Self.reasons).count == EffectFailureKind.allCases.count + 1)
    }

    @Test("the JSON form is pinned: what the disabled-effect store of a later issue will persist")
    func jsonForm() throws {
        #expect(try encoded(EffectDisableReason.failure(.pageFault)) == #"{"failure":{"_0":"pageFault"}}"#)
        #expect(try encoded(EffectDisableReason.overBudget) == #"{"overBudget":{}}"#)
    }
}

@Suite("DisabledEffectRecord")
struct DisabledEffectRecordTests {
    private static func record(
        _ id: EffectID = EffectID(origin: .package, key: "Ripple"), fingerprint: EffectFingerprint = stamp,
        reason: EffectDisableReason = .failure(.timeout), retries: Bool = false
    ) -> DisabledEffectRecord {
        DisabledEffectRecord(id: id, fingerprint: fingerprint, reason: reason, retriesAutomatically: retries)
    }

    @Test("a record is the same value only when id, fingerprint, reason and the retry flag all agree")
    func identity() {
        let base = Self.record()
        #expect(base == Self.record())
        #expect(base != Self.record(EffectID(origin: .package, key: "Glitch")))
        #expect(base != Self.record(EffectID(origin: .bundled, key: "Ripple")))
        #expect(base != Self.record(fingerprint: EffectFingerprint(value: "e33dd4f952f747d6")))
        #expect(base != Self.record(reason: .overBudget))
        #expect(base != Self.record(retries: true))
    }

    @Test("a list of records, the shape the store keeps, survives encode and decode", arguments: Seeds.range(0..<32))
    func codableRoundTrip(seed: UInt64) throws {
        var generator = SeededGenerator(seed: seed)
        let records = (0..<Int.random(in: 0...6, using: &generator)).map { index in
            Self.record(
                EffectID(origin: EffectOrigin.allCases.randomElement(using: &generator) ?? .bundled, key: "effect-\(index)"),
                fingerprint: EffectFingerprint(value: String(UInt64.random(in: 0...UInt64.max, using: &generator), radix: 16)),
                reason: ([EffectDisableReason.overBudget] + EffectFailureKind.allCases.map { .failure($0) }).randomElement(using: &generator)
                    ?? .overBudget,
                retries: Bool.random(using: &generator))
        }
        #expect(try roundTrip(records) == records)
    }

    @Test("the JSON form is pinned: what the disabled-effect store of a later issue will persist")
    func jsonForm() throws {
        let json = try encoded(Self.record(reason: .failure(.accessRevoked), retries: false))
        #expect(
            json
                == #"{"fingerprint":{"value":"321518f1bfcf7e49"},"id":{"key":"Ripple","origin":"package"},"reason":{"failure":{"_0":"accessRevoked"}},"retriesAutomatically":false}"#
        )
    }
}

@Suite("EffectPassOutcome")
struct EffectPassOutcomeTests {
    @Test("an outcome keeps the fingerprint it was stamped with and the result it carries")
    func carriesStampAndResult() {
        let succeeded = EffectPassOutcome(fingerprint: stamp, result: .success(timing))
        #expect(succeeded.fingerprint == stamp)
        #expect(succeeded.result == .success(timing))

        let failed = EffectPassOutcome(fingerprint: stamp, result: .failure(.unknown(code: 7)))
        #expect(failed.result == .failure(.unknown(code: 7)))
    }

    @Test("two outcomes are the same value only when stamp and result agree")
    func identity() {
        let base = EffectPassOutcome(fingerprint: stamp, result: .failure(.timeout))
        #expect(base == EffectPassOutcome(fingerprint: stamp, result: .failure(.timeout)))
        #expect(
            base != EffectPassOutcome(fingerprint: EffectFingerprint(value: "e33dd4f952f747d6"), result: .failure(.timeout)),
            "the stamp is part of it")
        #expect(base != EffectPassOutcome(fingerprint: stamp, result: .failure(.pageFault)))
        #expect(base != EffectPassOutcome(fingerprint: stamp, result: .failure(.unknown(code: 1))))
        #expect(
            EffectPassOutcome(fingerprint: stamp, result: .failure(.unknown(code: 1)))
                != EffectPassOutcome(fingerprint: stamp, result: .failure(.unknown(code: 2))))
        #expect(base != EffectPassOutcome(fingerprint: stamp, result: .success(timing)))
        #expect(
            EffectPassOutcome(fingerprint: stamp, result: .success(timing))
                != EffectPassOutcome(fingerprint: stamp, result: .success(GPUTiming(gpuStart: 0, gpuEnd: 0))))
    }

    @Test("a set holds one outcome per distinct stamp and result")
    func hashable() {
        let outcomes = [
            EffectPassOutcome(fingerprint: stamp, result: .success(timing)),
            EffectPassOutcome(fingerprint: stamp, result: .success(timing)),
            EffectPassOutcome(fingerprint: stamp, result: .failure(.timeout)),
        ]
        #expect(Set(outcomes).count == 2)
    }
}
