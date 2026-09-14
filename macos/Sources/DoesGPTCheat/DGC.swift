import Foundation

enum DGCError: LocalizedError {
    case notFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "dgc not found. Run ./install.sh in the does-gpt-cheat checkout."
        case .failed(let msg): return msg
        }
    }
}

/// Thin bridge to the `dgc` Python CLI. All logic stays in the plugin; the app only renders and dispatches.
enum DGC {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static func locate() -> String? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["DGC_BIN"], fm.fileExists(atPath: env) { return env }
        if let hint = try? String(contentsOfFile: home + "/.codex/does-gpt-cheat/dgc_bin", encoding: .utf8) {
            let p = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            if fm.fileExists(atPath: p) { return p }
        }
        let direct = home + "/does-gpt-cheat/plugin/skills/does-gpt-cheat/scripts/dgc"
        if fm.fileExists(atPath: direct) { return direct }
        let cacheRoot = home + "/.codex/plugins/cache/does-gpt-cheat/does-gpt-cheat"
        if let versions = try? fm.contentsOfDirectory(atPath: cacheRoot) {
            for v in versions.sorted().reversed() {
                let p = cacheRoot + "/" + v + "/skills/does-gpt-cheat/scripts/dgc"
                if fm.fileExists(atPath: p) { return p }
            }
        }
        return nil
    }

    private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env.removeValue(forKey: "CODEX_SANDBOX_NETWORK_DISABLED")
        return env
    }

    /// Runs `dgc <args>` and returns stdout. Throws with stderr on a non-zero exit.
    static func run(_ args: [String], timeout: TimeInterval = 30) async throws -> String {
        guard let bin = locate() else { throw DGCError.notFound }
        let env = environment()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["python3", bin] + args
                process.environment = env
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: DGCError.failed("cannot start python3: \(error.localizedDescription)"))
                    return
                }
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                if process.terminationStatus != 0 {
                    let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: DGCError.failed(msg?.isEmpty == false ? msg! : "dgc exited with \(process.terminationStatus)"))
                } else {
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                }
            }
        }
    }

    /// Fire-and-forget (background probes); output goes to the plugin's worker log.
    static func spawnDetached(_ args: [String]) throws {
        guard let bin = locate() else { throw DGCError.notFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", bin] + args
        process.environment = environment()
        let logPath = home + "/.codex/does-gpt-cheat/worker.log"
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        if let log = FileHandle(forWritingAtPath: logPath) {
            log.seekToEndOfFile()
            process.standardOutput = log
            process.standardError = log
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
    }
}
