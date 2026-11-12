/// One row of the camera menu as the Presenter shows it. The View only draws it; the wording of `title` is decided by the Presenter.
public struct CameraMenuOption: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// Whether this row is the choice in effect.
    public let isSelected: Bool

    public init(id: String, title: String, isSelected: Bool) {
        self.id = id
        self.title = title
        self.isSelected = isSelected
    }
}
