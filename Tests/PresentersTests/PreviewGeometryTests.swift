import Presenters
import TestSupport
import Testing

@Suite("PreviewGeometry")
struct PreviewGeometryTests {
    // The shape the preview pane is designed around, written out here rather than read from the type, so
    // that changing a constant turns these red.
    private let aspectRatio = 16.0 / 9.0
    private let maximumHeight = 240.0
    private let inset = 16.0

    @Test("a 640 wide container gives a 608 wide pane, held at the maximum height")
    func wideContainerHoldsTheMaximumHeight() {
        let geometry = PreviewGeometry(containerWidth: 640)

        #expect(abs(geometry.width - 608) < 1e-9)
        #expect(abs(geometry.height - maximumHeight) < 1e-9)
    }

    @Test("a 400 wide container gives a 368 wide pane at 16:9, which is 207 high")
    func narrowContainerKeepsTheShape() {
        let geometry = PreviewGeometry(containerWidth: 400)

        #expect(abs(geometry.width - 368) < 1e-9)
        #expect(abs(geometry.height - 207) < 1e-9)
    }

    @Test("the pane reaches the maximum height at the container width where 16:9 meets it, and not before")
    func capStartsAtTheBoundary() {
        let boundary = maximumHeight * aspectRatio + 2 * inset

        let atBoundary = PreviewGeometry(containerWidth: boundary)
        let below = PreviewGeometry(containerWidth: boundary - 1)
        let above = PreviewGeometry(containerWidth: boundary + 1)

        #expect(abs(atBoundary.height - maximumHeight) < 1e-9)
        #expect(below.height < maximumHeight)
        #expect(below.height <= maximumHeight + 1e-9)
        #expect(above.height <= maximumHeight + 1e-9)
        #expect(abs(above.height - maximumHeight) < 1e-9)
    }

    @Test(
        "a container that is negative or no wider than the insets gives an empty pane",
        arguments: [0.0, -100.0, 32.0])
    func containerWithNoRoomGivesAnEmptyPane(containerWidth: Double) {
        let geometry = PreviewGeometry(containerWidth: containerWidth)

        #expect(geometry.width == 0)
        #expect(geometry.height == 0)
    }

    @Test(
        "a container that is not finite gives an empty pane",
        arguments: [-Double.infinity, Double.infinity, Double.nan])
    func nonFiniteContainerGivesAnEmptyPane(containerWidth: Double) {
        let geometry = PreviewGeometry(containerWidth: containerWidth)

        #expect(geometry.width == 0)
        #expect(geometry.height == 0)
    }

    @Test(
        "for any finite container width, the pane fits between the insets and stays within the maximum height",
        arguments: Seeds.range(0..<64))
    func paneFitsTheContainerForAnyWidth(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let containerWidth = Double.random(in: 0...4_000, using: &generator)
        let usable = max(containerWidth - 2 * inset, 0)

        let geometry = PreviewGeometry(containerWidth: containerWidth)

        #expect(abs(geometry.width - usable) < 1e-9, "container \(containerWidth)")
        #expect(geometry.height >= 0 && geometry.height <= maximumHeight, "container \(containerWidth)")
        #expect(geometry.height * aspectRatio <= geometry.width + 1e-9, "container \(containerWidth)")
    }

    @Test("the minimum content height is at least twice the tallest pane, so the switch and the grid still fit below it")
    func minimumContentHeightLeavesRoomBelowTheTallestPane() {
        #expect(PreviewGeometry.minimumContentHeight >= 2 * maximumHeight)
    }

    @Test("the pane's corner radius is a positive number of points")
    func cornerRadiusIsPositive() {
        #expect(PreviewGeometry.cornerRadius > 0)
    }
}
