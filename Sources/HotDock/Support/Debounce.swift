import Foundation

/// Coalesces bursts of events (screen reconfiguration fires several notifications in a row)
/// into a single piece of work on the main queue.
final class Debouncer {
    private let delay: TimeInterval
    private var pending: DispatchWorkItem?

    init(delay: TimeInterval) { self.delay = delay }

    func call(_ block: @escaping () -> Void) {
        call(after: delay, block)
    }

    /// Same, with the delay supplied by the caller (used where the wait is user-configurable).
    func call(after delay: TimeInterval, _ block: @escaping () -> Void) {
        pending?.cancel()
        let item = DispatchWorkItem(block: block)
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() { pending?.cancel(); pending = nil }
}
