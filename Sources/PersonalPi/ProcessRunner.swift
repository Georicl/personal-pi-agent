import Foundation
import Darwin

/// Each RPC connection owns a writer; back-pressure must never block the UI
/// or delay writes to a replacement connection.
final class PiPipeWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "personal-pi.rpc-writer")
    private let lock = NSLock()
    private var cancelled = false

    init(handle: FileHandle) {
        self.handle = handle
        // A cancelled child closes its pipe. Turn EPIPE into a write error,
        // not a SIGPIPE that terminates the entire GUI process.
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func write(_ data: Data, onError: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            lock.lock()
            let shouldWrite = !cancelled
            lock.unlock()
            guard shouldWrite else { return }
            do { try handle.write(contentsOf: data) }
            catch { onError(error.localizedDescription) }
        }
    }

    func close() {
        lock.lock()
        cancelled = true
        lock.unlock()
        queue.async { [handle] in try? handle.close() }
    }
}

struct PiProcessResult: Sendable {
    let output: Data
    let error: Data
    let status: Int32
}

final class PiPreparedEnvironments: @unchecked Sendable {
    private let lock = NSLock()
    private var paths = Set<URL>()
    func contains(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return paths.contains(url)
    }
    func insert(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        paths.insert(url)
    }
    func remove(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        paths.remove(url)
    }
}

enum PiProcessError: LocalizedError {
    case timedOut, outputTooLarge, outputNotClosed
    var errorDescription: String? {
        switch self {
        case .timedOut: "Process timed out"
        case .outputTooLarge: "Process output exceeded the capture limit"
        case .outputNotClosed: "Process output did not close after termination"
        }
    }
}

/// Blocking one-shot runner. Call only on a worker queue, never on MainActor.
/// Interactive OAuth and streaming Pi RPC retain their dedicated transports.
enum PiProcessRunner {
    static func run(executable: URL, arguments: [String], workingDirectory: URL,
                    environment: [String: String], input: Data? = nil,
                    timeout: TimeInterval = 120, outputLimit: Int = 16 * 1024 * 1024) throws -> PiProcessResult {
        precondition(!Thread.isMainThread, "Run subprocesses off the UI thread")
        let process = Process()
        let capture = PiProcessCapture(limit: outputLimit)
        let stdin = Pipe()
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = capture.output
        process.standardError = capture.error
        try process.run()
        capture.start()
        // Blocking pipe I/O must not compete with CPU work on the shared
        // utility pool: even an exited child could otherwise hit the EOF grace
        // timeout before its queued drain starts on a busy CI/GUI process.
        Thread.detachNewThread {
            defer { try? stdin.fileHandleForWriting.close() }
            if let input { try? stdin.fileHandleForWriting.write(contentsOf: input) }
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 2)
            }
            capture.close()
            throw PiProcessError.timedOut
        }
        let captured = try capture.result()
        return PiProcessResult(output: captured.0, error: captured.1, status: process.terminationStatus)
    }
}

private final class PiProcessCapture: @unchecked Sendable {
    let output = Pipe()
    let error = Pipe()
    private let group = DispatchGroup()
    private let lock = NSLock()
    private let limit: Int
    private var outputData = Data()
    private var errorData = Data()
    private var exceededLimit = false

    init(limit: Int) { self.limit = limit }

    func start() {
        drain(output, isError: false)
        drain(error, isError: true)
    }

    func close() {
        try? output.fileHandleForReading.close()
        try? error.fileHandleForReading.close()
    }

    func result() throws -> (Data, Data) {
        guard group.wait(timeout: .now() + 2) == .success else {
            close()
            throw PiProcessError.outputNotClosed
        }
        lock.lock()
        defer { lock.unlock() }
        if exceededLimit { throw PiProcessError.outputTooLarge }
        return (outputData, errorData)
    }

    private func drain(_ pipe: Pipe, isError: Bool) {
        group.enter()
        Thread.detachNewThread { [self] in
            defer { group.leave() }
            while let chunk = try? pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                lock.lock()
                let count = isError ? errorData.count : outputData.count
                let remaining = max(0, limit - count)
                if chunk.count > remaining { exceededLimit = true }
                if isError { errorData.append(chunk.prefix(remaining)) }
                else { outputData.append(chunk.prefix(remaining)) }
                lock.unlock()
            }
        }
    }
}
