import Domain
import Foundation
import Testing

@testable import UserDefaultsGateway

/// The live smoke of the defaults gateway: a real `UserDefaults` suite named by a UUID, so the
/// user's own defaults are never read or written, and emptied again after every test.
///
/// One name serves the whole run and the suite is serialized, so that no two tests hold the
/// domain at once. Emptying a domain leaves an empty `<name>.plist` in `~/Library/Preferences`,
/// written by the OS when the process ends and out of the test's reach (a delete from the test
/// comes back at exit), so a name per test would leave one file per test on every run.
@Suite("KeyValueStoreGatewayImpl", .serialized, .timeLimit(.minutes(1)))
struct KeyValueStoreGatewayImplTests {
    private static let suiteName = UUID().uuidString

    /// Runs `body` over a gateway on the run's suite, then removes the suite's persistent domain
    /// and asserts it is gone.
    private func withSuite(_ body: (KeyValueStoreGatewayImpl, UserDefaults) throws -> Void) throws {
        let name = Self.suiteName
        let defaults = try #require(UserDefaults(suiteName: name))
        defer {
            defaults.removePersistentDomain(forName: name)
            #expect(defaults.persistentDomain(forName: name) == nil, "the suite \(name) is removed after the test")
        }
        try body(KeyValueStoreGatewayImpl(defaults: defaults), defaults)
    }

    @Test("a key that was never set reads as nil")
    func neverSet() throws {
        try withSuite { gateway, _ in
            #expect(gateway.string(forKey: "selectedEffect") == nil)
        }
    }

    @Test("set, then string, then remove, then nil")
    func roundTrip() throws {
        try withSuite { gateway, _ in
            gateway.set("package:glitch", forKey: "selectedEffect")
            #expect(gateway.string(forKey: "selectedEffect") == "package:glitch")
            gateway.removeValue(forKey: "selectedEffect")
            #expect(gateway.string(forKey: "selectedEffect") == nil)
        }
    }

    @Test("a value goes to the defaults it was given, under the key it was given")
    func writesThrough() throws {
        try withSuite { gateway, defaults in
            gateway.set("bundled:Chromatic Grain", forKey: "selectedEffect")
            #expect(defaults.string(forKey: "selectedEffect") == "bundled:Chromatic Grain")
            defaults.set("package:other", forKey: "selectedEffect")
            #expect(gateway.string(forKey: "selectedEffect") == "package:other")
        }
    }

    @Test("setting a key again replaces its value and leaves the other keys alone")
    func overwriteAndIndependence() throws {
        try withSuite { gateway, _ in
            gateway.set("one", forKey: "a")
            gateway.set("two", forKey: "b")
            gateway.set("three", forKey: "a")
            #expect(gateway.string(forKey: "a") == "three")
            #expect(gateway.string(forKey: "b") == "two")
            gateway.removeValue(forKey: "a")
            #expect(gateway.string(forKey: "a") == nil)
            #expect(gateway.string(forKey: "b") == "two")
        }
    }

    @Test("removing a key that is not there does nothing")
    func removeMissing() throws {
        try withSuite { gateway, _ in
            gateway.removeValue(forKey: "missing")
            gateway.set("kept", forKey: "other")
            gateway.removeValue(forKey: "missing")
            #expect(gateway.string(forKey: "missing") == nil)
            #expect(gateway.string(forKey: "other") == "kept")
        }
    }

    @Test("an empty string is a value, not an absent key")
    func emptyValue() throws {
        try withSuite { gateway, _ in
            gateway.set("", forKey: "empty")
            #expect(gateway.string(forKey: "empty") == "")
        }
    }
}
