import Combine
import Dependencies
import Domain

/// The effect parameter panel's display state (#113): the rows of the chosen effect's parameters, the
/// heading that names the effect, and the line for an effect with nothing to adjust. It turns
/// `EffectInteractor.state` into `@Published` values a View draws. The rows are a pure function of the
/// parameter states (`ParameterPanelRows.swift`) and the words are `ParameterPanelText.swift`.
///
/// It reads the Interactor the way `EffectPickerPresenter` does, and only observes: the Interactor's
/// lifecycle is the menu's Presenter's, so this one never calls its `start`, `stop` or `select`.
/// `start()` begins observing and `stop()` ends it; nothing starts on its own. A started Presenter that
/// is let go ends its observation.
@MainActor
public final class ParameterPanelPresenter: ObservableObject {
    /// One row per parameter of the chosen effect that can be drawn, in declaration order; empty until
    /// the first state arrives.
    @Published public private(set) var rows: [ParameterPanelRow] = []
    /// The chosen effect's name; empty until the first state arrives.
    @Published public private(set) var heading: String = ""
    /// What the panel says in place of rows when there are none; `nil` while there are rows and before
    /// the first state arrives.
    @Published public private(set) var emptyMessage: String?

    /// The title of the panel's window.
    public var windowTitle: String { parameterPanelWindowTitle }
    /// The title of the button that resets every parameter.
    public var resetTitle: String { parameterPanelResetTitle }
    /// `true` while the Presenter observes the Interactor: after `start()`, until `stop()` or the
    /// Presenter is let go. `false` when it was never started.
    public var isObserving: Bool { observation != nil }

    @Dependency(\.effectInteractor) private var interactor
    /// What a started Presenter holds; `nil` when it was never started or has been stopped. Letting it
    /// go ends the observation, so `stop()` and letting the Presenter go are one path.
    private var observation: CatalogStateObservation?

    public init() {}

    /// Observes the Interactor's state; the current one arrives first. Calling it again while started
    /// does nothing.
    public func start() {
        guard observation == nil else { return }
        observation = CatalogStateObservation(of: interactor.state) { [weak self] state in self?.apply(state) }
    }

    /// Ends the observation. The rows, the heading and the message stay those of the last state applied.
    public func stop() {
        observation = nil
    }

    private func apply(_ state: EffectCatalogState) {
        let rows = parameterPanelRows(of: state.parameters)
        let emptyMessage = rows.isEmpty ? parameterPanelEmptyMessage(of: state) : nil
        let heading = parameterPanelHeading(of: state)
        if self.rows != rows { self.rows = rows }
        if self.emptyMessage != emptyMessage { self.emptyMessage = emptyMessage }
        if self.heading != heading { self.heading = heading }
    }
}

/// The panel's setters and reset (#114). Each one only converts its value to the Interactor's type and
/// forwards it; clamping and snapping are the UseCase's. They do not depend on the observation, so
/// they reach the Interactor whether or not the Presenter was started.
extension ParameterPanelPresenter {
    /// Sends a `.float` value. A value that is not finite as a `Float` is not sent.
    public func setFloat(_ id: String, to value: Double) {
        let converted = Float(value)
        guard converted.isFinite else { return }
        interactor.setParameter(id, to: .float(converted))
    }

    /// Sends an `.int` value, clamped to the `Int32` range.
    public func setInt(_ id: String, to value: Int) {
        interactor.setParameter(id, to: .int(Int32(clamping: value)))
    }

    /// Sends a `.bool` value.
    public func setBool(_ id: String, to value: Bool) {
        interactor.setParameter(id, to: .bool(value))
    }

    /// Sends a `.color` value. If any component is not finite as a `Float`, nothing is sent.
    public func setColor(_ id: String, red: Double, green: Double, blue: Double, opacity: Double) {
        let r = Float(red)
        let g = Float(green)
        let b = Float(blue)
        let a = Float(opacity)
        guard [r, g, b, a].allSatisfy(\.isFinite) else { return }
        interactor.setParameter(id, to: .color(SIMD4<Float>(r, g, b, a)))
    }

    /// Sends a `.vector2` value. If either component is not finite as a `Float`, nothing is sent.
    public func setVector(_ id: String, x: Double, y: Double) {
        let fx = Float(x)
        let fy = Float(y)
        guard fx.isFinite, fy.isFinite else { return }
        interactor.setParameter(id, to: .vector2(SIMD2<Float>(fx, fy)))
    }

    /// Sends a `.choice` value: the index into the parameter's options, passed through as it is.
    public func setChoice(_ id: String, to index: Int) {
        interactor.setParameter(id, to: .choice(index))
    }

    /// Resets every parameter. Sends one reset and no value.
    public func reset() {
        interactor.resetParameters()
    }
}
