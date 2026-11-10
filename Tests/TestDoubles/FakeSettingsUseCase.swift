import Domain
import TestSupport

/// `SettingsUseCase` answering at once. `prepares` and `resets` count the calls to `prepareStore()`
/// and `resetAll()`, and `calls` takes the bare method name of each, in call order, so a sequence
/// that shares it with other fakes can be checked for order.
public final class FakeSettingsUseCase: SettingsUseCase, Sendable {
    public let prepares = Collector<Void>()
    public let resets = Collector<Void>()
    public let calls = Collector<String>()

    public init() {}

    public func prepareStore() async {
        prepares.append(())
        calls.append("prepareStore")
    }

    public func resetAll() async {
        resets.append(())
        calls.append("resetAll")
    }
}
