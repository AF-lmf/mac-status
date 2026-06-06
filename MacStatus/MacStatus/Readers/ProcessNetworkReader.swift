import Foundation

// MARK: - Per-Process Network Usage

struct ProcessNetworkUsage: Sendable, Equatable {
    let processName: String
    let processIdentifier: Int32?
    let downloadBytesPerSec: Double
    let uploadBytesPerSec: Double

    var totalBytesPerSec: Double {
        downloadBytesPerSec + uploadBytesPerSec
    }
}

enum ProcessNetworkUsageResult: Sendable, Equatable {
    case processes([ProcessNetworkUsage])
    case idle
    case unavailable(String)
}

/// Reads per-process network deltas on demand.
///
/// Aggregate menu bar throughput uses low-overhead `getifaddrs()`. Per-process
/// attribution is not exposed by that API, so this reader invokes macOS `nettop`
/// only when the user opens the menu.
enum ProcessNetworkReader {

    private static let nettopPath = "/usr/bin/nettop"

    static func readTopProcesses(limit: Int = 5, timeout: TimeInterval = 3.0) -> ProcessNetworkUsageResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nettopPath)
        process.arguments = [
            "-P",
            "-d",
            "-L", "2",
            "-s", "1",
            "-x",
            "-n", // Skip hostname resolution — without this, nettop blocks
                   // for ~5s on reverse-DNS lookups when run from a non-TTY
                   // Process(), exceeding the 3s timeout and always returning
                   // .unavailable. With -n, completes in ~1s.
            "-J", "bytes_in,bytes_out",
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return .unavailable("Unable to start nettop.")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return .unavailable("nettop sampling timed out.")
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .unavailable(errorText.isEmpty ? "nettop exited with an error." : errorText)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        return parseTopProcesses(from: output, limit: limit)
    }

    private static func parseTopProcesses(
        from output: String,
        limit: Int
    ) -> ProcessNetworkUsageResult {
        var samples: [[ProcessNetworkUsage]] = []
        var currentSample: [ProcessNetworkUsage] = []

        for line in output.split(whereSeparator: \.isNewline) {
            let columns = line
                .split(separator: ",", omittingEmptySubsequences: false)
                .map(String.init)

            guard columns.count >= 3 else { continue }

            if columns[0].isEmpty && columns[1] == "bytes_in" {
                if !currentSample.isEmpty {
                    samples.append(currentSample)
                    currentSample = []
                }
                continue
            }

            guard let usage = parseUsage(columns: columns) else { continue }
            currentSample.append(usage)
        }

        if !currentSample.isEmpty {
            samples.append(currentSample)
        }

        guard let latestSample = samples.last else {
            return .unavailable("No nettop samples were returned.")
        }

        let activeProcesses = latestSample
            .filter { $0.totalBytesPerSec > 0 }
            .sorted {
                if $0.totalBytesPerSec == $1.totalBytesPerSec {
                    return $0.processName < $1.processName
                }
                return $0.totalBytesPerSec > $1.totalBytesPerSec
            }

        let topProcesses = Array(activeProcesses.prefix(max(limit, 0)))
        guard !topProcesses.isEmpty else {
            return .idle
        }

        return .processes(topProcesses)
    }

    private static func parseUsage(columns: [String]) -> ProcessNetworkUsage? {
        let identity = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty,
              let downloadBytes = Double(columns[1]),
              let uploadBytes = Double(columns[2]) else {
            return nil
        }

        let parsedIdentity = parseProcessIdentity(identity)
        return ProcessNetworkUsage(
            processName: parsedIdentity.name,
            processIdentifier: parsedIdentity.pid,
            downloadBytesPerSec: downloadBytes,
            uploadBytesPerSec: uploadBytes
        )
    }

    private static func parseProcessIdentity(_ identity: String) -> (name: String, pid: Int32?) {
        guard let separator = identity.lastIndex(of: ".") else {
            return (identity, nil)
        }

        let pidText = identity[identity.index(after: separator)...]
        guard let pid = Int32(pidText) else {
            return (identity, nil)
        }

        let name = String(identity[..<separator])
        return (name.isEmpty ? identity : name, pid)
    }
}
