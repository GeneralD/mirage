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
