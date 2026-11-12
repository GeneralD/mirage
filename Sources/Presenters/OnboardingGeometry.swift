/// The onboarding window's layout (#223): the height of the block that shows the compiler message of
/// an effect that failed, as a pure value so that the layout is tested here. The View only maps the
/// height to a frame (`Views` is coverage-ignored and holds no logic).
///
/// The block is one line per newline plus one, a trailing newline not counted, `lineHeight` each and
/// `messagePadding` above and below, kept between `minimumMessageHeight` and `maximumMessageHeight`.
/// Wrapped text is not counted: the View scrolls it. A message that is nil or only whitespace has no
/// block at all, so its height is 0.
public struct OnboardingGeometry: Sendable, Hashable {
    /// The width of the onboarding window.
    public static let windowWidth = 480.0
    /// The height the onboarding window opens at, before its content is measured.
    public static let initialWindowHeight = 480.0
    /// The margin on each side of the window's content.
    public static let inset = 24.0
    /// The gap between two blocks of the window.
    public static let spacing = 16.0
    /// The height of one line of the message.
    public static let lineHeight = 15.0
    /// The space above and below the lines of the message.
    public static let messagePadding = 8.0
    /// The shortest the message block gets while it is shown.
    public static let minimumMessageHeight = 60.0
    /// The tallest the message block gets; a longer message scrolls inside it.
    public static let maximumMessageHeight = 240.0

    /// How tall the message block is; 0 when there is no message to show.
    public let messageHeight: Double

    public init(message: String?) {
        guard let message, message.contains(where: { !$0.isWhitespace }) else {
            messageHeight = 0
            return
        }
        let height = Double(Self.lineCount(of: message)) * Self.lineHeight + 2 * Self.messagePadding
        messageHeight = min(max(height, Self.minimumMessageHeight), Self.maximumMessageHeight)
    }

    /// The lines of `message`, split at each newline (a CRLF is one newline). Empty lines in the middle
    /// count; the empty piece after a trailing newline does not.
    private static func lineCount(of message: String) -> Int {
        let pieces = message.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return pieces.last?.isEmpty == true ? pieces.count - 1 : pieces.count
    }
}
