import Domain
import TestDoubles
import Testing

@testable import EffectCatalogUseCase

// The neighbouring-effect rule behind next and previous effect. Each sentence of the issue's
// Interface is one test named after it; the rows of a test are that sentence's cases.

private let a = EffectID.package("a")
private let b = EffectID.package("b")
private let c = EffectID.package("c")
private let d = EffectID.package("d")

private func ready(_ id: EffectID) -> EffectCatalogEntry { .fixture(id) }
private func broken(_ id: EffectID) -> EffectCatalogEntry { .fixture(id, availability: .broken(.manifestMissing)) }

private let abc = [ready(a), ready(b), ready(c)]
private let withBroken = [ready(a), broken(b), ready(c)]

/// One case of a table: the catalog, the chosen effect, the step, and the neighbour the rule must give.
struct NeighborRow: Sendable {
    let entries: [EffectCatalogEntry]
    let selection: EffectID?
    let step: EffectStep
    let expected: EffectID?
}

@Suite("effectNeighbor", .timeLimit(.minutes(1)))
struct EffectNeighborTests {
    @Test(
        "with a, b and c all ready and b chosen, next is c and previous is a",
        arguments: [
            NeighborRow(entries: abc, selection: b, step: .next, expected: c),
            NeighborRow(entries: abc, selection: b, step: .previous, expected: a),
        ])
    func middleChoiceMovesToItsNeighbours(_ row: NeighborRow) {
        #expect(effectNeighbor(of: row.selection, in: row.entries, step: row.step) == row.expected)
    }

    @Test(
        "choosing c, next wraps round to a; choosing a, previous wraps round to c",
        arguments: [
            NeighborRow(entries: abc, selection: c, step: .next, expected: a),
            NeighborRow(entries: abc, selection: a, step: .previous, expected: c),
        ])
    func choosingAnEndWrapsRoundToTheOther(_ row: NeighborRow) {
        #expect(effectNeighbor(of: row.selection, in: row.entries, step: row.step) == row.expected)
    }

    @Test(
        "a broken b between two ready ones is passed over: from a next is c, from c previous is a",
        arguments: [
            NeighborRow(entries: withBroken, selection: a, step: .next, expected: c),
            NeighborRow(entries: withBroken, selection: c, step: .previous, expected: a),
            NeighborRow(entries: withBroken, selection: a, step: .previous, expected: c),
            NeighborRow(entries: withBroken, selection: c, step: .next, expected: a),
        ])
    func brokenEntryIsSkippedInBothDirections(_ row: NeighborRow) {
        #expect(effectNeighbor(of: row.selection, in: row.entries, step: row.step) == row.expected)
    }

    @Test(
        "a lone ready effect that is chosen has no neighbour in either direction",
        arguments: [
            NeighborRow(entries: [broken(b), ready(a), broken(c)], selection: a, step: .next, expected: nil),
            NeighborRow(entries: [broken(b), ready(a), broken(c)], selection: a, step: .previous, expected: nil),
        ])
    func loneChosenEffectHasNoNeighbour(_ row: NeighborRow) {
        #expect(effectNeighbor(of: row.selection, in: row.entries, step: row.step) == row.expected)
    }

    @Test(
        "with no entries, or none ready, there is no neighbour",
        arguments: [
            NeighborRow(entries: [], selection: nil, step: .next, expected: nil),
            NeighborRow(entries: [], selection: nil, step: .previous, expected: nil),
            NeighborRow(entries: [broken(a), broken(b)], selection: a, step: .next, expected: nil),
            NeighborRow(entries: [broken(a), broken(b)], selection: nil, step: .previous, expected: nil),
        ])
    func noReadyEntryHasNoNeighbour(_ row: NeighborRow) {
        #expect(effectNeighbor(of: row.selection, in: row.entries, step: row.step) == row.expected)
    }

    @Test(
        "a selection that is nil or not ready moves next to the first ready one and previous to the last",
        arguments: [
            NeighborRow(entries: abc, selection: nil, step: .next, expected: a),
            NeighborRow(entries: abc, selection: nil, step: .previous, expected: c),
            NeighborRow(entries: abc, selection: d, step: .next, expected: a),
            NeighborRow(entries: abc, selection: d, step: .previous, expected: c),
            NeighborRow(entries: withBroken, selection: b, step: .next, expected: a),
            NeighborRow(entries: withBroken, selection: b, step: .previous, expected: c),
        ])
    func unchosenSelectionStartsFromTheEnds(_ row: NeighborRow) {
        #expect(effectNeighbor(of: row.selection, in: row.entries, step: row.step) == row.expected)
    }

    @Test(
        "a lone ready effect is the neighbour in both directions when a broken one is chosen",
        arguments: [
            NeighborRow(entries: [ready(a), broken(b)], selection: b, step: .next, expected: a),
            NeighborRow(entries: [ready(a), broken(b)], selection: b, step: .previous, expected: a),
        ])
    func loneReadyEffectIsNeighbourWhenBrokenIsChosen(_ row: NeighborRow) {
        #expect(effectNeighbor(of: row.selection, in: row.entries, step: row.step) == row.expected)
    }
}
