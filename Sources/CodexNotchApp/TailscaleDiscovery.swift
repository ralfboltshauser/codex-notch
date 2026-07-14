import Foundation

enum TailscaleDiscovery {
    static func localIPv4() -> String? {
        let candidates = [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale",
        ]
        for executable in candidates where FileManager.default.isExecutableFile(atPath: executable) {
            guard let output = try? run(executable, arguments: ["ip", "-4"]),
                  let address = output.split(whereSeparator: { $0.isWhitespace }).first else { continue }
            return String(address)
        }
        return nil
    }

    private static func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "CodexNotch", code: Int(process.terminationStatus))
        }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
