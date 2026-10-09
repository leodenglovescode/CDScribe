// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct CommandResult: Sendable {
    public var status: Int32
    public var output: Data
    public var errorOutput: Data
    public var log: String { String(decoding: errorOutput, as: UTF8.self) }
}

// Process and pipe state are protected by a lock; only the worker owns their lifecycle.
private final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func start(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.process = process
        try process.run()
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }
    func finish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        process = nil; return cancelled
    }
}
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        if data.count > 8 * 1024 * 1024 { data.removeFirst(data.count - 8 * 1024 * 1024) }
    }
    func value() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}
private func waitForPipes(_ group: DispatchGroup) { group.wait() }

public struct ProcessRunner: Sendable {
    public init() {}
    public func run(_ executable: URL, _ arguments: [String], directory: URL? = nil, line: (@Sendable (String) -> Void)? = nil) async throws -> CommandResult {
        let control = ProcessControl()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = executable; process.arguments = arguments
                process.currentDirectoryURL = directory
                var environment = ProcessInfo.processInfo.environment
                environment["LC_ALL"] = "C"; environment["AV_LOG_FORCE_NOCOLOR"] = "1"
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                process.environment = environment
                process.standardInput = FileHandle.nullDevice
                let stdout = Pipe(), stderr = Pipe()
                process.standardOutput = stdout; process.standardError = stderr
                let out = OutputBuffer(), err = OutputBuffer(), group = DispatchGroup()
                try control.start(process)
                for (pipe, buffer) in [(stdout, out), (stderr, err)] {
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        defer { group.leave() }
                        var pending = Data()
                        while true {
                            let chunk = pipe.fileHandleForReading.availableData
                            if chunk.isEmpty { break }
                            buffer.append(chunk)
                            if let line {
                                pending.append(chunk)
                                while let boundary = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                                    line(String(decoding: pending[..<boundary], as: UTF8.self))
                                    pending.removeSubrange(...boundary)
                                }
                                if pending.count > 65536 { pending.removeAll() }
                            }
                        }
                        if !pending.isEmpty { line?(String(decoding: pending, as: UTF8.self)) }
                    }
                }
                process.waitUntilExit(); waitForPipes(group)
                if control.finish() { throw CancellationError() }
                return CommandResult(status: process.terminationStatus, output: out.value(), errorOutput: err.value())
            }.value
        } onCancel: { control.cancel() }
    }
    public func checked(_ executable: URL, _ arguments: [String], directory: URL? = nil, line: (@Sendable (String) -> Void)? = nil) async throws -> CommandResult {
        let result = try await run(executable, arguments, directory: directory, line: line)
        guard result.status == 0 else {
            throw CDScribeError.message("\(executable.lastPathComponent) exited with code \(result.status).\n\(result.log.suffix(4000))")
        }
        return result
    }
}

public struct BackendTools: Sendable {
    public var ffmpeg: URL?
    public var ffprobe: URL?
    public var cdrdao: URL?
    public init(ffmpeg: URL? = nil, ffprobe: URL? = nil, cdrdao: URL? = nil) {
        self.ffmpeg = ffmpeg ?? Self.find("ffmpeg"); self.ffprobe = ffprobe ?? Self.find("ffprobe"); self.cdrdao = cdrdao ?? Self.find("cdrdao")
    }
    public static func find(_ name: String) -> URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)").path
        for path in [bundled, "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"] {
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }
}
