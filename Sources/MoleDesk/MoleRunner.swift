import Foundation

struct CommandResult: Sendable {
    let command: String
    let exitCode: Int32
    let output: String
}

enum MoleRunner {
    static let searchPaths = [
        "/opt/homebrew/bin/mo",
        "/usr/local/bin/mo",
        "/usr/bin/mo",
        "/bin/mo"
    ]

    static func locateMole() -> String? {
        for path in searchPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let result = runExecutable("/usr/bin/env", arguments: ["which", "mo"])
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }

    static func runMole(arguments: [String]) async -> CommandResult {
        guard let molePath = locateMole() else {
            return CommandResult(
                command: "mo \(arguments.joined(separator: " "))",
                exitCode: 127,
                output: """
                Mole CLI was not found.

                Install it first:
                  brew install mole

                Then reopen SweepDock or click Refresh.
                """
            )
        }

        return await Task.detached(priority: .userInitiated) {
            runExecutable(molePath, arguments: arguments)
        }.value
    }

    private static func runExecutable(_ executable: String, arguments: [String]) -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM": "xterm-256color",
            "LC_ALL": "en_US.UTF-8"
        ]

        do {
            try process.run()
        } catch {
            return CommandResult(
                command: ([executable] + arguments).joined(separator: " "),
                exitCode: 126,
                output: "Failed to launch command: \(error.localizedDescription)"
            )
        }

        let stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = [
            String(data: stdout, encoding: .utf8),
            String(data: stderr, encoding: .utf8)
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return CommandResult(
            command: ([executable] + arguments).joined(separator: " "),
            exitCode: process.terminationStatus,
            output: output.isEmpty ? "(No output)" : output
        )
    }
}
