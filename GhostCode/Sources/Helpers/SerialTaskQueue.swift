/// Runs async jobs one at a time on the main actor, in the order they were enqueued.
@MainActor
final class SerialTaskQueue {
    private var tail: Task<Void, Never>?

    func enqueue(_ job: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await job()
        }
    }
}
