import Foundation

// stdout belongs exclusively to the browser's length-prefixed protocol.
let input = FileHandle.standardInput
let output = FileHandle.standardOutput
var result: [String: Any]
if CommandLine.arguments.dropFirst().first != BrowserHostCore.allowedOrigin {
    result = ["ok": false, "error": "This browser extension is not approved."]
} else {
    do {
        let payload = try BrowserHostCore.readMessage(from: input)
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("com.snapdrive.screenshot/Browser Captures", isDirectory: true)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app", FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/SnapDrive").path) else { throw BrowserHostCore.Failure.unavailable }
        result = try BrowserHostCore.handle(payload, directory: cache) { file in
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", app.path, file.path]
            process.standardOutput = FileHandle.standardError; process.standardError = FileHandle.standardError
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw BrowserHostCore.Failure.unavailable }
        }
    } catch let error as BrowserHostCore.Failure { result = ["ok": false, "error": error.rawValue] }
    catch { result = ["ok": false, "error": "Could not transfer this capture. Try again."] }
}
if let response = try? BrowserHostCore.response(result) { try? output.write(contentsOf: response) }
