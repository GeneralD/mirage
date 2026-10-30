import Combine
import Dependencies
import Domain

/// The effect picker's display state (#12): the grid's cells, the search above them and the
/// menu's line about how the last attempt to run the chosen effect went. It turns
/// `EffectInteractor.state` into `@Published` values a View draws; the words, flags and placeholder
/// tiles are pure functions (`EffectPickerText.swift`), and drawing them is not its job.
///
/// It reads the same Interactor as `MenuBarPresenter`, so what the picker shows as chosen is what
/// the menu checks, and a choice made in either shows in both. It only observes: the Interactor's
/// lifecycle is the menu's Presenter's, which the Router starts at launch, and a picker that
/// started or stopped it would restart or end the catalog the menu draws. `start()` begins
/// observing and `stop()` ends it; the Router calls them when it opens and closes the picker's
/// window, and nothing starts on its own. A started Presenter that is let go ends its observation.
@MainActor
public final class EffectPickerPresenter: ObservableObject {
    /// The cells that match `query`, in the catalog's order (the bundled effect first); empty until
    /// the first state arrives.
    @Published public private(set) var cells: [EffectPickerCell] = []
    /// One line about the chosen effect when the last attempt to run it failed, as the menu says it;
    /// `nil` when it is running or nothing was attempted.
    @Published public private(set) var status: String?
    /// What the grid says in place of cells when the search hides every effect; `nil` otherwise.
    @Published public private(set) var emptyMessage: String?
    /// The search the field above the grid edits: a cell is shown when its name or author contains
    /// it. Empty, or only whitespace, shows every effect. `stop()` clears it.
    @Published public var query = "" {
        didSet { show() }
    }

    @Dependency(\.effectInteractor) private var interactor
    /// What a started Presenter holds; `nil` when it was never started or has been stopped. Letting
    /// it go ends the observation, so `stop()` and letting the Presenter go are one path.
    private var observation: CatalogStateObservation?
    /// The last state applied, kept so that a new search filters it without asking the Interactor.
    private var state: EffectCatalogState?

    public init() {}

    /// Observes the Interactor's state; the current one arrives first. Calling it again while
    /// started does nothing.
    public func start() {
        guard observation == nil else { return }
        observation = CatalogStateObservation(of: interactor.state) { [weak self] state in self?.apply(state) }
    }

    /// Ends the observation and clears the search, so the picker opens on every effect next time.
    /// The cells stay those of the last state applied, even when a state had already been sent and
    /// not yet applied.
    public func stop() {
        observation = nil
        query = ""
    }

    /// Chooses the effect, whichever cell it is: a broken package's answer comes back through the
    /// Interactor's state, as it does from the menu.
    public func select(_ id: EffectID) {
        interactor.select(id)
    }

    private func apply(_ state: EffectCatalogState) {
        self.state = state
        show()
    }

    private func show() {
        guard let state else { return }
        let cells = pickerCells(of: state, matching: query)
        let status = MenuBarText.status(of: state)
        let emptyMessage = pickerEmptyMessage(of: state, matching: query)
        if self.cells != cells { self.cells = cells }
        if self.status != status { self.status = status }
        if self.emptyMessage != emptyMessage { self.emptyMessage = emptyMessage }
    }
}
