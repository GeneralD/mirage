/// One window of the app that the gallery opens over fixture data, with no camera.
struct GalleryScreen {
    /// The name the command line gives it: lowercase ASCII words joined by hyphens, such as `effect-picker`.
    let name: String
    /// The line `--list` prints after the name: what the screen shows. One line, no tab.
    let summary: String
    /// Opens the screen's window over its fixture data and shows it. Answers what must stay alive while the window is open (usually an `AppRouter`).
    let open: @MainActor () -> AnyObject
}

extension GalleryScreen: Equatable {
    /// Names are unique (`GalleryScreensTests`), so the name is the identity.
    static func == (lhs: GalleryScreen, rhs: GalleryScreen) -> Bool {
        lhs.name == rhs.name
    }
}
