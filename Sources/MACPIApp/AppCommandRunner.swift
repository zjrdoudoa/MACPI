import Foundation

struct AppCommandResult {
    let exitCode: Int32
    let output: String
}

enum AppCommandRunner {
    static func run(_ executable: String, _ arguments: [String]) -> AppCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return AppCommandResult(
                exitCode: process.terminationStatus,
                output: String(data: data, encoding: .utf8) ?? ""
            )
        } catch {
            return AppCommandResult(exitCode: 127, output: String(describing: error))
        }
    }
}
