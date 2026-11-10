import Presenters
import TestSupport
import Testing

@Suite("ParameterPanelGeometry")
struct ParameterPanelGeometryTests {
    // The panel's sizes and gaps, written out here rather than read from the type, so that changing a
    // constant turns these red.
    private let inset = 16.0
    private let spacing = 12.0
    private let axisSpacing = 4.0
    private let labelLineLimit = 2
    private let minimumLabelWidth = 80.0
    private let maximumLabelWidth = 160.0
    private let labelShare = 0.3
    private let minimumControlWidth = 120.0
    private let valueWidth = 48.0
    private let initialWidth = 420.0
    private let initialHeight = 440.0
    private let minimumHeight = 240.0
    private let minimumWidth = 244.0

    @Test("the panel's sizes and gaps are the values it was designed around")
    func constantsAreTheDesignedValues() {
        #expect(ParameterPanelGeometry.inset == inset)
        #expect(ParameterPanelGeometry.spacing == spacing)
        #expect(ParameterPanelGeometry.axisSpacing == axisSpacing)
        #expect(ParameterPanelGeometry.labelLineLimit == labelLineLimit)
        #expect(ParameterPanelGeometry.minimumLabelWidth == minimumLabelWidth)
        #expect(ParameterPanelGeometry.maximumLabelWidth == maximumLabelWidth)
        #expect(ParameterPanelGeometry.labelShare == labelShare)
        #expect(ParameterPanelGeometry.minimumControlWidth == minimumControlWidth)
        #expect(ParameterPanelGeometry.valueWidth == valueWidth)
        #expect(ParameterPanelGeometry.initialWidth == initialWidth)
        #expect(ParameterPanelGeometry.initialHeight == initialHeight)
        #expect(ParameterPanelGeometry.minimumHeight == minimumHeight)
    }

    @Test("the narrowest width at which a label and a control fit side by side is 244 points")
    func minimumWidthIsTheNarrowestSideBySideWidth() {
        #expect(ParameterPanelGeometry.minimumWidth == minimumWidth)
    }

    @Test(
        "a width gives the label and control widths the panel was laid out for",
        arguments: [
            (0.0, 80.0, 120.0),
            (244, 80, 120),
            (300, 80.4, 175.6),
            (420, 116.4, 259.6),
            (600, 160, 396),
            (1_000, 160, 796),
        ])
    func examples(width: Double, labelWidth: Double, controlWidth: Double) {
        let geometry = ParameterPanelGeometry(width: width)

        #expect(abs(geometry.labelWidth - labelWidth) < 1e-9)
        #expect(abs(geometry.controlWidth - controlWidth) < 1e-9)
    }

    @Test(
        "a width that is negative or not finite leaves no room beyond the narrowest columns",
        arguments: [-100.0, -.infinity, .infinity, .nan])
    func degenerateWidths(width: Double) {
        let geometry = ParameterPanelGeometry(width: width)

        #expect(abs(geometry.labelWidth - minimumLabelWidth) < 1e-9)
        #expect(abs(geometry.controlWidth - minimumControlWidth) < 1e-9)
    }

    @Test(
        "every width gives a label from 80 to 160 points wide and a control at least 120 points wide",
        arguments: Seeds.range(0..<64))
    func labelAndControlStayWithinTheirBounds(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let width = Double.random(in: 0...4_000, using: &generator)

        let geometry = ParameterPanelGeometry(width: width)

        #expect(geometry.labelWidth >= minimumLabelWidth, "width \(width)")
        #expect(geometry.labelWidth <= maximumLabelWidth, "width \(width)")
        #expect(geometry.controlWidth >= minimumControlWidth, "width \(width)")
    }

    @Test(
        "from the minimum width up, the label, the gap and the control fill the width between the insets",
        arguments: Seeds.range(0..<64))
    func labelGapAndControlFillTheRow(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let width = Double.random(in: 0...4_000, using: &generator)
        let usable = width - 2 * inset

        let geometry = ParameterPanelGeometry(width: width)
        let filled = geometry.labelWidth + spacing + geometry.controlWidth

        #expect(width < minimumWidth || abs(filled - usable) < 1e-9, "width \(width): the row adds up to \(filled), not \(usable)")
    }
}
