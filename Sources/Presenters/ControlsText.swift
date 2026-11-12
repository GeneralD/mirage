// The icon and the readout of the menu bar's controls, as pure functions of the controls' state, so
// that `MenuBarPresenter` only moves them into its `@Published` values.

/// The menu bar's icon. While the effect is bypassed the plain camera is shown, whatever the chosen
/// effect's state is, since a bypassed effect does not run; otherwise a problem with the chosen effect
/// shows as a warning, and no problem as the filtered camera.
func menuBarIconName(isBypassed: Bool, hasProblem: Bool) -> String {
    if isBypassed { return "camera" }
    return hasProblem ? "exclamationmark.triangle" : "camera.filters"
}

/// The frame-rate readout, `"<n> fps"`, or `nil` when there is no rate to show (zero or less).
func frameRateLine(framesPerSecond: Int) -> String? {
    framesPerSecond > 0 ? "\(framesPerSecond) fps" : nil
}
