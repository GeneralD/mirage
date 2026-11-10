/// One row of the effect's parameter panel as the Presenter shows it (#111): the parameter's name
/// and the control a View draws for it. The Presenter decides the values; the View only draws them.
public struct ParameterPanelRow: Sendable, Hashable, Identifiable {
    /// The parameter's `id`, which is the field name the shader reads.
    public let id: String
    /// What the row says the control is for.
    public let label: String
    public let control: ParameterPanelControl

    public init(id: String, label: String, control: ParameterPanelControl) {
        self.id = id
        self.label = label
        self.control = control
    }
}

/// The control a panel row draws. A closed set, so the View switches over it exhaustively: a new
/// control is a compile error there rather than a row that is never drawn.
public enum ParameterPanelControl: Sendable, Hashable {
    case slider(ParameterPanelSlider)
    case stepper(value: Int, range: ClosedRange<Int>, text: String)
    case toggle(isOn: Bool)
    /// sRGB components in `0...1`, opacity last.
    case color(red: Double, green: Double, blue: Double, opacity: Double)
    /// Two sliders for a point: the X axis, then the Y axis.
    case vector(x: ParameterPanelSlider, y: ParameterPanelSlider)
    case picker(selection: Int, options: [String])
}

/// A slider the View draws: its value is already inside `range`, and `text` is the value as the
/// row shows it.
public struct ParameterPanelSlider: Sendable, Hashable {
    /// The name VoiceOver reads.
    public let title: String
    /// A short mark drawn before the slider; only the axes of a vector have one (`X` and `Y`).
    public let caption: String?
    public let value: Double
    public let range: ClosedRange<Double>
    /// The grid the drag snaps to, or `nil` for a free drag.
    public let step: Double?
    /// The value written with as many decimals as the step has.
    public let text: String

    public init(title: String, caption: String?, value: Double, range: ClosedRange<Double>, step: Double?, text: String) {
        self.title = title
        self.caption = caption
        self.value = value
        self.range = range
        self.step = step
        self.text = text
    }
}
