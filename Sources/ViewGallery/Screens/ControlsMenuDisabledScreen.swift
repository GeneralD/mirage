import Domain

extension GalleryScreen {
    /// The menu over the catalog in which health has switched two effects off: the chosen `Glitch` and `Ripple`, each with a Re-enable row.
    static var controlsMenuDisabled: GalleryScreen {
        GalleryScreen(
            name: "controls-menu-disabled",
            summary: "Effects menu: the chosen effect and another were disabled by the health policy, each with a Re-enable row"
        ) {
            openControlsMenu(showing: effectPickerDisabledCatalog, controls: ControlsState(isBypassed: false, framesPerSecond: 30))
        }
    }
}
