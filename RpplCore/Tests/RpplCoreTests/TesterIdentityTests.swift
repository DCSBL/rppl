import Foundation
import Testing
@testable import RpplCore

@Suite("TesterIdentity")
struct TesterIdentityTests {
    @Test func persistsInDefaults() {
        let suite = "RpplCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = TesterIdentity.resolve(store: defaults)
        let second = TesterIdentity.resolve(store: defaults)
        #expect(first == second)
        #expect(UUID(uuidString: first) != nil)
    }

    @Test func createsNewIdWhenMissing() {
        let suite = "RpplCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(defaults.string(forKey: TesterIdentity.defaultsKey) == nil)
        let id = TesterIdentity.resolve(store: defaults)
        #expect(defaults.string(forKey: TesterIdentity.defaultsKey) == id)
    }
}
