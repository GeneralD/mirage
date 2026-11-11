import Presenters
import SwiftUI

/// The menu item that opens the onboarding window (#232), placed above the effects menu in the host's
/// `MenuBarExtra`. It is declaration only: the title is `onboardingMenuTitle`, and choosing the item calls
/// `open`, which the App layer wires to `OnboardingRouter.openOnboarding()`. It holds no state and decides nothing.
public struct OnboardingMenuItem: View {
    private let open: @MainActor () -> Void

    public init(open: @escaping @MainActor () -> Void) {
        self.open = open
    }

    public var body: some View {
        Button(onboardingMenuTitle) { open() }
        Divider()
    }
}
