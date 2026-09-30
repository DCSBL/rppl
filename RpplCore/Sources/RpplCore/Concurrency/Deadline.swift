import Foundation

/// Run async work with a hard deadline that returns on time even when the work never finishes.
///
/// A task-group timeout does not do that: leaving the group waits for every child, so a child
/// stuck on a callback that never comes (a hung `healthd`) holds the caller forever. Here the work
/// runs in an unstructured task; whichever of work or timer finishes first resumes the caller,
/// and the work is cancelled (it may keep running if it ignores cancellation).
///
/// Rule: never implement a timeout with a task group around unstructured work or callback-based
/// APIs; use `Deadline.run`.
public enum Deadline {
    public struct Expired: Error, Equatable, Sendable {
        public let label: String
        public let seconds: TimeInterval
    }

    public static func run<T: Sendable>(
        _ seconds: TimeInterval,
        label: String,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = ResumeOnce<T>()
        return try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            let work = Task {
                do {
                    gate.resume(with: .success(try await operation()))
                } catch {
                    gate.resume(with: .failure(error))
                }
            }
            let timer = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if gate.resume(with: .failure(Expired(label: label, seconds: seconds))) {
                    work.cancel()
                }
            }
            gate.onResume { timer.cancel() }
        }
    }
}

/// Resumes a continuation exactly once, whoever gets there first.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pending: Result<T, Error>?
    private var done = false
    private var cleanup: (@Sendable () -> Void)?

    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let pending {
            self.pending = nil
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func onResume(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        if done {
            lock.unlock()
            action()
            return
        }
        cleanup = action
        lock.unlock()
    }

    /// - Returns: `true` when this call resumed the caller.
    @discardableResult
    func resume(with result: Result<T, Error>) -> Bool {
        lock.lock()
        guard !done else {
            lock.unlock()
            return false
        }
        done = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil {
            pending = result
        }
        let cleanup = self.cleanup
        self.cleanup = nil
        lock.unlock()
        continuation?.resume(with: result)
        cleanup?()
        return true
    }
}
