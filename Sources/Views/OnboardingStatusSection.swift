import Domain
import Presenters
import SwiftUI

/// The status part of the onboarding window (#228): the virtual camera's status line with its symbol, the buttons that open the
/// System Settings panes for its approval, and the notice when System Settings did not open. The buttons and the notice are the
/// Presenter's values as they are; the symbol and colour of a tone are the pure mapping below.
struct OnboardingStatusSection: View {
    @ObservedObject var presenter: OnboardingPresenter

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingGeometry.spacing) {
            HStack(alignment: .top) {
                Image(systemName: presenter.status.tone.symbolName)
                    .foregroundStyle(presenter.status.tone.color)
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(presenter.status.headline)
                        .font(.title3.weight(.semibold))
                    if !presenter.status.detail.isEmpty {
                        Text(presenter.status.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !presenter.paneActions.isEmpty {
                HStack {
                    ForEach(presenter.paneActions, id: \.pane) { action in
                        Button(action.title) { Task { await presenter.openSettings(action.pane) } }
                    }
                }
                .buttonStyle(.bordered)
            }
            if let notice = presenter.settingsNotice {
                Text(notice.text)
                    .font(.callout)
                    .foregroundStyle(notice.tone.color)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension OnboardingTone {
    /// The SF Symbol that stands for the tone.
    var symbolName: String {
        switch self {
        case .neutral: "circle.dashed"
        case .progress: "hourglass"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    /// The colour the tone is drawn in: the secondary colour while nothing is wrong or right yet, green, orange or red after that.
    var color: Color {
        switch self {
        case .neutral, .progress: .secondary
        case .success: .green
        case .warning: .orange
        case .failure: .red
        }
    }
}
