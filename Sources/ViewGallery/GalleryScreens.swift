/// The screens the gallery can open, in the order `--list` prints them.
///
/// To add a screen: put `extension GalleryScreen { static var xxx: GalleryScreen { ... } }` in `Screens/XxxScreen.swift`, then append
/// one line `.xxx,` just before the closing bracket below. Never edit, reorder or reformat the lines already there:
/// `.gitattributes` merges this file with `merge=union`, which keeps both sides' added lines when two changes append together.
var galleryScreens: [GalleryScreen] {
    [
        .effectPicker,
        .effectPickerFailed,
        .effectPickerDisabled,
        .controlsMenu,
        .controlsMenuBypassed,
        .cameraMenu,
        .cameraMenuMissing,
        .cameraMenuNone,
        .parameterPanel,
        .parameterPanelEmpty,
        .settings,
        .settingsAttention,
    ]
}
