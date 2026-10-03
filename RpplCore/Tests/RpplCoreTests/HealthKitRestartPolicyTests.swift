import Testing
@testable import RpplCore

@Suite("HealthKitRestartPolicy")
struct HealthKitRestartPolicyTests {
    @Test func retriesUpToTheLimit() {
        #expect(HealthKitRestartPolicy.shouldRetry(attempt: 1, healthDenied: false))
        #expect(HealthKitRestartPolicy.shouldRetry(attempt: HealthKitRestartPolicy.maxAttempts, healthDenied: false))
        #expect(!HealthKitRestartPolicy.shouldRetry(attempt: HealthKitRestartPolicy.maxAttempts + 1, healthDenied: false))
        #expect(!HealthKitRestartPolicy.shouldRetry(attempt: 0, healthDenied: false))
    }

    @Test func deniedIsNeverRetried() {
        #expect(!HealthKitRestartPolicy.shouldRetry(attempt: 1, healthDenied: true))
    }
}
