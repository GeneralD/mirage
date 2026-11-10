import Domain
import Testing

@testable import Presenters

@Suite("ParameterPanelRows")
struct ParameterPanelRowsTests {
    @Test("the Ripple example's six parameters become the six rows of the spec, in manifest order")
    func rippleExampleBecomesSixRows() {
        let states = [
            state("strength", "Strength", .float(min: 0, max: 1, step: 0.01, defaultValue: 0.5), .float(0.25)),
            state("rings", "Rings", .int(min: 1, max: 16, defaultValue: 4), .int(8)),
            state("inverted", "Inverted", .bool(defaultValue: false), .bool(true)),
            state("tint", "Tint", .color(defaultValue: [1, 0.8, 0.6, 1]), .color([1, 0.5, 0.25, 1])),
            state("center", "Center", .vector2(min: [0, 0], max: [1, 1], defaultValue: [0.5, 0.5]), .vector2([0.25, 0.75])),
            state("mode", "Mode", .choice(options: ["Soft", "Hard"], defaultIndex: 0), .choice(1)),
        ]

        let rows = parameterPanelRows(of: states)

        #expect(
            rows == [
                ParameterPanelRow(
                    id: "strength", label: "Strength",
                    control: .slider(
                        ParameterPanelSlider(
                            title: "Strength", caption: nil, value: 0.25, range: 0...1, step: Double(Float(0.01)), text: "0.25"))),
                ParameterPanelRow(id: "rings", label: "Rings", control: .stepper(value: 8, range: 1...16, text: "8")),
                ParameterPanelRow(id: "inverted", label: "Inverted", control: .toggle(isOn: true)),
                ParameterPanelRow(
                    id: "tint", label: "Tint", control: .color(red: 1, green: 0.5, blue: 0.25, opacity: 1)),
                ParameterPanelRow(
                    id: "center", label: "Center",
                    control: .vector(
                        x: ParameterPanelSlider(title: "Center X", caption: "X", value: 0.25, range: 0...1, step: nil, text: "0.25"),
                        y: ParameterPanelSlider(title: "Center Y", caption: "Y", value: 0.75, range: 0...1, step: nil, text: "0.75"))),
                ParameterPanelRow(
                    id: "mode", label: "Mode", control: .picker(selection: 1, options: ["Soft", "Hard"])),
            ])
    }

    @Test("no states give no rows")
    func emptyStatesGiveNoRows() {
        #expect(parameterPanelRows(of: []).isEmpty)
    }

    @Test("a value outside its range is drawn at the nearest end of the range")
    func valueOutsideRangeIsDrawnAtTheNearestEnd() {
        let states = [
            state("high", "High", .float(min: 0, max: 1, step: nil, defaultValue: 0), .float(5)),
            state("low", "Low", .float(min: 0, max: 1, step: nil, defaultValue: 0), .float(-3)),
            state("count", "Count", .int(min: 1, max: 16, defaultValue: 4), .int(99)),
            state("center", "Center", .vector2(min: [0, 0], max: [1, 1], defaultValue: [0.5, 0.5]), .vector2([5, -3])),
            state("tint", "Tint", .color(defaultValue: [1, 1, 1, 1]), .color([1.5, -0.5, 0.5, 2])),
        ]

        let rows = parameterPanelRows(of: states)

        #expect(
            rows == [
                ParameterPanelRow(
                    id: "high", label: "High",
                    control: .slider(
                        ParameterPanelSlider(title: "High", caption: nil, value: 1, range: 0...1, step: nil, text: "1.00"))),
                ParameterPanelRow(
                    id: "low", label: "Low",
                    control: .slider(
                        ParameterPanelSlider(title: "Low", caption: nil, value: 0, range: 0...1, step: nil, text: "0.00"))),
                ParameterPanelRow(id: "count", label: "Count", control: .stepper(value: 16, range: 1...16, text: "16")),
                ParameterPanelRow(
                    id: "center", label: "Center",
                    control: .vector(
                        x: ParameterPanelSlider(title: "Center X", caption: "X", value: 1, range: 0...1, step: nil, text: "1.00"),
                        y: ParameterPanelSlider(title: "Center Y", caption: "Y", value: 0, range: 0...1, step: nil, text: "0.00"))),
                ParameterPanelRow(
                    id: "tint", label: "Tint", control: .color(red: 1, green: 0, blue: 0.5, opacity: 1)),
            ])
    }

    @Test(
        "a choice outside its options is drawn at the default index, not at the nearest option",
        arguments: [7, -1])
    func choiceOutsideOptionsFallsBackToTheDefaultIndex(index: Int) {
        let states = [
            state("mode", "Mode", .choice(options: ["Soft", "Hard"], defaultIndex: 0), .choice(index))
        ]

        #expect(
            parameterPanelRows(of: states)
                == [ParameterPanelRow(id: "mode", label: "Mode", control: .picker(selection: 0, options: ["Soft", "Hard"]))])
    }

    @Test("a value is written with as many decimals as its step has", arguments: stepDecimalCases)
    func valueIsWrittenWithTheDecimalsOfItsStep(step: Float?, text: String) {
        let states = [
            state("x", "X", .float(min: 0, max: 10, step: step, defaultValue: 3), .float(3))
        ]

        #expect(
            parameterPanelRows(of: states)
                == [
                    ParameterPanelRow(
                        id: "x", label: "X",
                        control: .slider(
                            ParameterPanelSlider(
                                title: "X", caption: nil, value: 3, range: 0...10, step: step.map { Double($0) }, text: text)))
                ])
    }

    @Test(
        "a step that is zero, negative, NaN or infinite is treated as no step",
        arguments: [Float(0), -1, Float.nan, Float.infinity, -Float.infinity])
    func degenerateStepIsTreatedAsNoStep(step: Float) {
        let states = [
            state("x", "X", .float(min: 0, max: 10, step: step, defaultValue: 3), .float(3))
        ]

        #expect(
            parameterPanelRows(of: states)
                == [
                    ParameterPanelRow(
                        id: "x", label: "X",
                        control: .slider(
                            ParameterPanelSlider(title: "X", caption: nil, value: 3, range: 0...10, step: nil, text: "3.00")))
                ])
    }

    @Test(
        "a state that cannot be drawn is left out and the rows around it stay",
        arguments: undrawableStates)
    func undrawableStateIsLeftOutAndTheRowsAroundItStay(bad: EffectParameterState) {
        let states = [
            state("before", "Before", .bool(defaultValue: false), .bool(false)),
            bad,
            state("after", "After", .bool(defaultValue: false), .bool(true)),
        ]

        #expect(
            parameterPanelRows(of: states)
                == [
                    ParameterPanelRow(id: "before", label: "Before", control: .toggle(isOn: false)),
                    ParameterPanelRow(id: "after", label: "After", control: .toggle(isOn: true)),
                ])
    }

    @Test("an Int32 at the edge of its type is drawn without overflowing")
    func int32EdgeIsDrawnWithoutOverflow() {
        let states = [
            state("n", "N", .int(min: Int32.min, max: Int32.max, defaultValue: 0), .int(Int32.max))
        ]

        #expect(
            parameterPanelRows(of: states)
                == [
                    ParameterPanelRow(
                        id: "n", label: "N",
                        control: .stepper(
                            value: 2_147_483_647, range: -2_147_483_648...2_147_483_647, text: "2147483647"))
                ])
    }
}

/// The text of a value at each step, with the value 3 on a range of 0...10: the decimals are the
/// step's, and two when there is no step.
private let stepDecimalCases: [(Float?, String)] = [
    (nil, "3.00"),
    (1, "3"),
    (0.5, "3.0"),
    (0.01, "3.00"),
    (0.001, "3.000"),
    (0.25, "3.00"),
    (0.0001, "3.0000"),
    (Float(1) / 3, "3.0000"),
]

/// States that have no row: each one is a kind whose range or value cannot be drawn.
private let undrawableStates: [EffectParameterState] = [
    state("bad", "Bad", .float(min: 1, max: 1, step: nil, defaultValue: 1), .float(1)),
    state("bad", "Bad", .float(min: 0, max: .nan, step: nil, defaultValue: 0), .float(0)),
    state("bad", "Bad", .float(min: 0, max: 1, step: nil, defaultValue: 0), .float(.nan)),
    state("bad", "Bad", .int(min: 2, max: 1, defaultValue: 1), .int(1)),
    state("bad", "Bad", .vector2(min: [0, 1], max: [1, 1], defaultValue: [0.5, 1]), .vector2([0.5, 1])),
    state("bad", "Bad", .vector2(min: [.nan, 0], max: [1, 1], defaultValue: [0.5, 0.5]), .vector2([0.5, 0.5])),
    state("bad", "Bad", .choice(options: [], defaultIndex: 0), .choice(0)),
    state("bad", "Bad", .choice(options: ["Soft", "Hard"], defaultIndex: 5), .choice(7)),
    state("bad", "Bad", .bool(defaultValue: false), .float(1)),
    state("bad", "Bad", .color(defaultValue: [0, 0, 0, 1]), .color([.nan, 0, 0, 1])),
]

private func state(
    _ id: String, _ label: String, _ kind: EffectParameterKind, _ value: EffectParameterValue
) -> EffectParameterState {
    EffectParameterState(spec: EffectParameterSpec(id: id, label: label, kind: kind), value: value)
}
