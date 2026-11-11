import Presenters
import SwiftUI

/// The onboarding window (#228), drawn from an `OnboardingPresenter`: the virtual camera's status and the buttons that open its
/// System Settings approval, then the diagnostics of an effect that failed and the support log. It maps the Presenter's values to
/// pixels and decides nothing: the words, the buttons, the notices and the height of the message block are the Presenter's and
/// `OnboardingGeometry`'s.
public struct OnboardingView: View {
    @ObservedObject private var presenter: OnboardingPresenter

    public init(presenter: OnboardingPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnboardingGeometry.spacing) {
                OnboardingStatusSection(presenter: presenter)
                Divider()
                OnboardingDiagnosticsSection(presenter: presenter)
            }
            .padding(OnboardingGeometry.inset)
        }
        .frame(minWidth: OnboardingGeometry.windowWidth)
    }
}
