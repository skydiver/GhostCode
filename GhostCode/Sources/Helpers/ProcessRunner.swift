import Foundation
import os

/// Runs a short-lived helper process and collects its stdout without blocking
/// on a full pipe, an inherited stdin, or a process that never exits.
enum ProcessRunner {
    /// Runs `process` and returns its stdout, or nil if it could not start or did
    /// not exit within `timeout` (it is then terminated). Stdin and stderr are
    /// set to the null device unless the caller configured them.
    static func output(of process: Process, timeout: TimeInterval) async -> Data? {
        await withCheckedContinuation { continuation in
            let stdout = Pipe()
            let run = Run(continuation: continuation, output: stdout.fileHandleForReading)
            process.standardOutput = stdout
            if process.standardInput == nil { process.standardInput = FileHandle.nullDevice }
            if process.standardError == nil { process.standardError = FileHandle.nullDevice }

            // Read as data arrives so output larger than the pipe buffer can't stall the child.
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                // Past EOF the handler would keep firing with empty data.
                if chunk.isEmpty { handle.readabilityHandler = nil }
                run.received(chunk)
            }
            process.terminationHandler = { _ in run.exited() }

            do {
                try process.run()
            } catch {
                run.finish(nil)
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                run.timedOut(process)
            }
        }
    }

    /// Completion state for one run, shared by the pipe, termination and timeout callbacks.
    private final class Run: Sendable {
        private struct State {
            var continuation: CheckedContinuation<Data?, Never>?
            var data = Data()
            var reachedEOF = false
            var hasExited = false
        }

        private let state: OSAllocatedUnfairLock<State>
        private let output: FileHandle

        init(continuation: CheckedContinuation<Data?, Never>, output: FileHandle) {
            self.state = OSAllocatedUnfairLock(initialState: State(continuation: continuation))
            self.output = output
        }

        func received(_ chunk: Data) {
            complete { state in
                if chunk.isEmpty {
                    state.reachedEOF = true
                } else {
                    state.data.append(chunk)
                }
                return state.reachedEOF && state.hasExited ? .done(state.data) : .pending
            }
        }

        func exited() {
            complete { state in
                state.hasExited = true
                return state.reachedEOF ? .done(state.data) : .pending
            }
        }

        func timedOut(_ process: Process) {
            complete { state in
                // The process finished, but a background child it started still
                // holds the pipe open. Its output so far is complete.
                if state.hasExited { return .done(state.data) }
                process.terminate()
                return .done(nil)
            }
        }

        func finish(_ result: Data?) {
            complete { _ in .done(result) }
        }

        /// Applies `update` under the lock and resumes once it yields a result.
        private func complete(_ update: (inout State) -> Outcome) {
            let resume: (CheckedContinuation<Data?, Never>, Data?)? = state.withLock { state in
                guard let continuation = state.continuation else { return nil }
                guard case .done(let result) = update(&state) else { return nil }
                state.continuation = nil
                return (continuation, result)
            }
            guard let (continuation, result) = resume else { return }
            output.readabilityHandler = nil
            continuation.resume(returning: result)
        }
    }

    private enum Outcome {
        case pending
        /// Finished: stdout, or nil when the run failed or timed out.
        case done(Data?)
    }
}
