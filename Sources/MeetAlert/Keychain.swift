import Foundation

/// Generic-password items for the ntfy secrets (access token, fallback topic URL): never in config.json.
/// Created and read by Apple-signed `/usr/bin/security`, never `SecItemAdd`: with no Team ID an item this
/// app creates is tied to this build's cdhash, so every rebuild would ask for the login password. A
/// CLI-made item trusts the CLI (partition `apple-tool:`), so every build reads it silently.
enum Keychain {
    static let tokenService = "com.roy.meetalert.ntfy-token"
    static let fallbackService = "com.roy.meetalert.ntfy-fallback"
    private static let account = "meetalert"

    static func get(_ service: String) -> String {
        security(["find-generic-password", "-s", service, "-a", account, "-g"]).flatMap(password) ?? ""
    }

    /// Empty value deletes the item.
    static func set(_ service: String, _ value: String) {
        guard get(service) != value else { return }
        guard !value.isEmpty else {
            _ = security(["delete-generic-password", "-s", service, "-a", account])
            return
        }
        // Secret goes in as hex on stdin, never argv: other users' `ps` can read argv.
        // shortcut: `security -i` truncates lines past ~4 KB (a ~2 KB secret); fine for ntfy tokens and URLs.
        let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        _ = security(["-i"], stdin: "add-generic-password -U -s \"\(service)\" -a \"\(account)\" -X \(hex)\n")
    }

    /// The `-g` stderr line: `password: "text"` when printable, `password: 0xHEX` otherwise.
    static func password(_ stderr: String) -> String? {
        guard let line = stderr.split(separator: "\n").last(where: { $0.hasPrefix("password: ") }) else { return nil }
        let value = line.dropFirst("password: ".count)
        if value.hasPrefix("0x") {
            let hex = Array(value.dropFirst(2).prefix(while: \.isHexDigit))
            guard hex.count % 2 == 0 else { return nil }
            let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { UInt8(String(hex[$0..<$0 + 2]), radix: 16) }
            return String(decoding: bytes, as: UTF8.self)
        }
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return nil }
        return String(value.dropFirst().dropLast())
    }

    /// Runs `/usr/bin/security`; its stderr on exit 0, nil otherwise (44 = not found).
    private static func security(_ args: [String], stdin: String? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = args
        let stderr = Pipe(), input = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        if stdin != nil { process.standardInput = input }
        do { try process.run() } catch { return nil }
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
        }
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
