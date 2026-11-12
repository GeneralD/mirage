import Domain
import Presenters
import SwiftUI

/// The menu bar's icon, drawn from a `MenuBarPresenter`: its `iconName` is the picture and the product's
/// name is its accessibility label. Which icon shows is the Presenter's, so this view holds no branch;
/// `@ObservedObject` redraws it whenever the Presenter's values change.
public struct MenuBarLabel: View {
    @ObservedObject private var presenter: MenuBarPresenter

    public init(presenter: MenuBarPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        Image(systemName: presenter.iconName)
            .accessibilityLabel(ProductIdentity.displayName)
    }
}
