import Domain

// The words of the effect parameter panel, as pure functions of the catalog's state, so that
// `ParameterPanelPresenter` only moves them into its `@Published` values. The heading's name follows
// the rule the menu and the picker use (`MenuBarText`): the selection's display name, or its key when
// the listing has no entry for it, so the three never name the same effect differently.

/// The panel window's title, as the window and its Presenter both say it.
let parameterPanelWindowTitle = "Adjust Effect"

/// The title of the button that puts every parameter of the chosen effect back to its default.
let parameterPanelResetTitle = "Reset"

/// The name of the chosen effect, as the panel's heading shows it.
func parameterPanelHeading(of state: EffectCatalogState) -> String {
    state.entries.first { $0.id == state.selection }?.displayName ?? state.selection.key
}

/// What the panel says in place of rows when there are none to draw: the chosen effect has no
/// parameters, or none of them can be drawn.
func parameterPanelEmptyMessage(of state: EffectCatalogState) -> String {
    "\(parameterPanelHeading(of: state)) has no parameters"
}
