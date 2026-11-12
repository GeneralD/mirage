/// The onboarding window as `AppRouter` drives it (#229): shown when the Router opens onboarding, closed when the Router stops.
/// The window reports a close through the `onClose` it was made with, whoever closed it, with itself as the argument, so the
/// Router can tell its open window from one it has already let go. The live window is `OnboardingWindowImpl`; a test passes a
/// fake through the Router's window factory, so no suite opens a real window.
@MainActor
public protocol OnboardingWindow: AnyObject {
    /// Brings the application and the window to the front.
    func show()
    /// Closes the window; its `onClose` runs as it does for a close from the title bar.
    func close()
}

extension OnboardingWindowImpl: OnboardingWindow {}
