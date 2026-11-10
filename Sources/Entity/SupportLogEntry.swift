/// One line of this process's unified log as the support log reads it: when it was
/// written (seconds since 1970-01-01 UTC), the category it was filed under and its
/// composed message. Pure data; which lines are kept and how they are shown is decided above.
public struct SupportLogEntry: Sendable, Hashable {
    public let timestamp: Double
    public let category: String
    public let message: String

    public init(timestamp: Double, category: String, message: String) {
        self.timestamp = timestamp
        self.category = category
        self.message = message
    }
}
