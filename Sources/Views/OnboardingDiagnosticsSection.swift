import Domain
import Presenters
import SwiftUI

/// The diagnostics part of the onboarding window (#228): why the chosen effect failed, shown only while the catalog has a status
/// line for it, with the compiler's message in a block of the height `OnboardingGeometry` gives; and the support log, with its save
/// button, a spinner while the save runs, and the notice of the last save. The words and the heights are the Presenter's.
struct OnboardingDiagnosticsSection: View {
    @ObservedObject var presenter: OnboardingPresenter

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingGeometry.spacing) {
            if let effectStatus = presenter.effectStatus {
                VStack(alignment: .leading) {
                    Text(onboardingCompilerMessageTitle)
                        .font(.headline)
                    Text(effectStatus)
                        .font(.callout)
                    if let message = presenter.compilerMessage {
                        ScrollView {
                            Text(message)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(OnboardingGeometry.messagePadding)
                        }
                        .frame(height: presenter.geometry.messageHeight)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.secondary)
                        }
                    }
                }
            }
            VStack(alignment: .leading) {
                Text(onboardingSupportLogTitle)
                    .font(.headline)
                Text(onboardingSupportLogHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(presenter.supportLogButtonTitle) { Task { await presenter.exportSupportLog() } }
                        .disabled(presenter.isSavingLog)
                    if presenter.isSavingLog {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            if let notice = presenter.logNotice {
                Text(notice.text)
                    .font(.callout)
                    .foregroundStyle(notice.tone.color)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
