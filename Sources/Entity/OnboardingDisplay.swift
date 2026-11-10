/// How the onboarding window tints the virtual camera's status. The Presenter chooses it for each
/// install status; the View maps it to a colour.
public enum OnboardingTone: Sendable, Hashable {
    case neutral
    case progress
    case success
    case warning
    case failure
}

/// The status line of the onboarding window: the words that say where the virtual camera stands,
/// with the tone that goes with them.
public struct OnboardingStatusDisplay: Sendable, Hashable {
    public let tone: OnboardingTone
    public let headline: String
    public let detail: String

    public init(tone: OnboardingTone, headline: String, detail: String) {
        self.tone = tone
        self.headline = headline
        self.detail = detail
    }
}

/// A button that opens a System Settings pane, with the title it shows.
public struct OnboardingPaneAction: Sendable, Hashable {
    public let pane: SystemSettingsPane
    public let title: String

    public init(pane: SystemSettingsPane, title: String) {
        self.pane = pane
        self.title = title
    }
}

/// A one-line message the onboarding window shows under its controls.
public struct OnboardingNotice: Sendable, Hashable {
    public let tone: OnboardingTone
    public let text: String

    public init(tone: OnboardingTone, text: String) {
        self.tone = tone
        self.text = text
    }
}
