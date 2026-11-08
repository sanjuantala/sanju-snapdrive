import Foundation
import ImageIO
import Vision

/// Local, one-request native messaging protocol. It accepts pixels only, never paths or commands.
enum BrowserHostCore {
    static let extensionID = "onchblaldmgmldajccljklnjonkicpnf"
    static let allowedOrigin = "chrome-extension://\(extensionID)/"
    static let maxMessageBytes = 57 * 1024 * 1024
    static let maxPNGBytes = 40 * 1024 * 1024
    static let maxPixels = 40_000_000
    static let pngPrefix = "data:image/png;base64,"
    enum Failure: String, Error {
        case framing = "Invalid browser message."
        case unsupported = "Unsupported browser request."
        case image = "The browser capture is not a valid PNG."
        case large = "Screenshot is too large. Capture a smaller region in the Mac app."
        case recognition = "Could not read the selected text. Try a tighter selection with clear text."
        case unavailable = "Could not open Sanju’s SnapDrive. Reinstall the browser connection from the app."
    }
    static func readExactly(_ count: Int, from input: FileHandle) throws -> Data {
        var result = Data(); result.reserveCapacity(count)
        while result.count < count {
            guard let chunk = try input.read(upToCount: count - result.count), !chunk.isEmpty else { throw Failure.framing }
            result.append(chunk)
        }
        return result
    }
    static func readMessage(from input: FileHandle) throws -> Data {
        let header = try readExactly(4, from: input)
        let length = header.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << (8 * $1.offset)) }
        guard length > 0, length <= maxMessageBytes else { throw Failure.framing }
        return try readExactly(Int(length), from: input)
    }
    static func response(_ object: [String: Any]) throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var size = UInt32(payload.count).littleEndian
        return withUnsafeBytes(of: &size) { Data($0) } + payload
    }
    static func png(from request: [String: Any], action: String = "capture") throws -> Data {
        guard let version = request["version"] as? Int, version == 1, request["action"] as? String == action, let string = request["png"] as? String, string.hasPrefix(pngPrefix) else { throw Failure.unsupported }
        guard string.utf8.count <= maxMessageBytes - 128 else { throw Failure.large }
        guard let data = Data(base64Encoded: String(string.dropFirst(pngPrefix.count))) else { throw Failure.image }
        guard data.count <= maxPNGBytes else { throw Failure.large }
        guard data.starts(with: [137,80,78,71,13,10,26,10]), let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetType(source) as String? == "public.png", CGImageSourceGetCount(source) == 1, CGImageSourceGetStatus(source) == .statusComplete, let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { throw Failure.image }
        guard width <= 32768, height <= 32768, width <= maxPixels / height else { throw Failure.large }
        if action == "recognize" {
            guard width <= 8192, height <= 8192, width <= 12_000_000 / height else { throw Failure.large }
        }
        return data
    }
    static func recognizeText(_ data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.image }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
        catch {
            request.usesCPUOnly = true
            do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
            catch { throw Failure.recognition }
        }
        let lines = (request.results ?? []).sorted { lhs,rhs in
            let left = lhs.boundingBox, right = rhs.boundingBox
            let rowA = Int((left.midY * 200).rounded()), rowB = Int((right.midY * 200).rounded())
            return rowA == rowB ? left.minX < right.minX : rowA > rowB
        }.prefix(1000).compactMap { $0.topCandidates(1).first?.string }
        return String(lines.joined(separator: "\n").prefix(32000))
    }
    static func store(_ png: Data, directory: URL, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let entries = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey])) ?? []
        let candidates = entries.filter { $0.lastPathComponent.hasPrefix("Browser-") && $0.pathExtension == "png" }.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { return nil }
            return (url, values.creationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        var keptBytes = 0
        for (index, item) in candidates.enumerated() {
            keptBytes += item.2
            if index >= 19 || keptBytes > 200 * 1024 * 1024 || now.timeIntervalSince(item.1) > 24 * 3600 { try? fm.removeItem(at: item.0) }
        }
        let file = directory.appendingPathComponent("Browser-\(UUID().uuidString).png")
        try png.write(to: file, options: [.withoutOverwriting])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }
    static func handle(_ payload: Data, directory: URL, recognize: (Data) throws -> String = recognizeText, open: (URL) throws -> Void) throws -> [String: Any] {
        guard let request = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw Failure.unsupported }
        if request["action"] as? String == "recognize" {
            let text = try recognize(png(from: request, action: "recognize"))
            return ["ok": true, "version": 1, "text": String(text.prefix(32000))]
        }
        let data = try png(from: request)
        let file = try store(data, directory: directory)
        do { try open(file) } catch { try? FileManager.default.removeItem(at: file); throw Failure.unavailable }
        return ["ok": true, "version": 1]
    }
}
