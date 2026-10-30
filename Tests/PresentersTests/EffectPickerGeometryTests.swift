import Presenters
import TestSupport
import Testing

@Suite("EffectPickerGeometry")
struct EffectPickerGeometryTests {
    // The layout the picker is designed around, written out here rather than read from the type, so
    // that changing a constant turns these red.
    private let minimumCellWidth = 120.0
    private let spacing = 12.0
    private let inset = 16.0
    private let maximumColumns = 32

    @Test(
        "a width gives the columns and the cell width it was laid out for",
        arguments: [
            (0.0, 1, 0.0),
            (32, 1, 0),
            (100, 1, 68),
            (152, 1, 120),
            (283, 1, 251),
            (284, 2, 120),
            (640, 4, 143),
            (1_000, 7, (968.0 - 72) / 7),
        ])
    func examples(width: Double, columns: Int, cellWidth: Double) {
        let geometry = EffectPickerGeometry(width: width)

        #expect(geometry.columns == columns)
        #expect(abs(geometry.cellWidth - cellWidth) < 1e-9)
    }

    @Test(
        "a width that is negative or not finite is a single column with no room",
        arguments: [-100.0, -.infinity, .infinity, .nan])
    func degenerateWidths(width: Double) {
        let geometry = EffectPickerGeometry(width: width)

        #expect(geometry.columns == 1)
        #expect(geometry.cellWidth == 0)
    }

    @Test("the column count stops at the maximum on a width no window has, and the cells widen instead")
    func columnsStopAtTheMaximum() {
        let geometry = EffectPickerGeometry(width: 1e12)

        #expect(geometry.columns == maximumColumns)
        #expect(geometry.cellWidth > minimumCellWidth)
    }

    @Test(
        "the row holds as many cells as fit at the minimum width, and they fill it between the insets",
        arguments: Seeds.range(0..<64))
    func rowsFitAndFill(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let width = Double.random(in: 0...4_000, using: &generator)
        let usable = max(width - 2 * inset, 0)

        let geometry = EffectPickerGeometry(width: width)

        #expect(geometry.columns == fitting(in: usable), "width \(width)")
        let filled = Double(geometry.columns) * geometry.cellWidth + Double(geometry.columns - 1) * spacing
        #expect(abs(filled - usable) < 1e-6, "width \(width): the cells and gaps add up to \(filled), not \(usable)")
        #expect(geometry.columns == 1 || geometry.cellWidth >= minimumCellWidth, "width \(width)")
    }

    /// The model: the most columns, from 1 to the maximum, whose cells of the minimum width and the gaps
    /// between them fit in `usable`, counted one by one rather than by the type's division.
    private func fitting(in usable: Double) -> Int {
        (1...maximumColumns).last { count in
            Double(count) * minimumCellWidth + Double(count - 1) * spacing <= usable
        } ?? 1
    }
}
