import Foundation

/// Fully intercepted network checks: never contacts Google or another service.
@MainActor
enum DriveLinkChecks {
    static let viewer = "https://drive.google.com/file/d/file_fixture/view?usp=drivesdk&resourcekey=0-example-key%2Bvalue"
    static let refreshedViewer = "https://drive.google.com/file/d/file_fixture/view?usp=sharing&resourcekey=0-new-key%2Bvalue"
    static let imageBytes = Data("fake screenshot bitmap".utf8)

    static func run() async throws {
        try await privateUpload()
        try await publicLink()
        try await sharingFailureAndRetry()
        try await linkRefreshFailure()
        try await inheritedAccess()
        try codableAndValidation()
        try fingerprints()
        try await configurationReadiness()
        print("Drive link checks passed: private/public access, resource keys, sharing fallback, link-only retries, no duplicate uploads, metadata refresh failure, Codable round-trip.")
    }

    static func withService(_ operation: (DriveService, DriveMockTrace) async throws -> Void) async throws {
        let suite = "SnapDrive-DriveLinkChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("folder_fixture", forKey: "drive.folderID")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DriveMockProtocol.self]
        let session = URLSession(configuration: configuration)
        let trace = DriveMockTrace()
        DriveMockProtocol.trace = trace
        defer {
            session.invalidateAndCancel()
            DriveMockProtocol.trace = nil
            defaults.removePersistentDomain(forName: suite)
        }
        let service = DriveService(session: session, defaults: defaults, transientAccessToken: "fixture-token-never-sent")
        try await operation(service, trace)
    }

    static func privateUpload() async throws {
        try await withService { service, trace in
            trace.responder = baseUploadResponder
            let result = try await service.uploadAndLink(data: imageBytes, name: "Retina Screenshot.png", sharing: .privateAccess)
            try check(result.fileID == "file_fixture", "Must retain uploaded file ID")
            try check(result.driveURL.absoluteString == viewer && result.shareURL == result.driveURL, "The complete Google viewer URL must be preserved exactly")
            try check(!result.isPublic && !result.shortened && result.warning == nil, "Private upload must not invent sharing or shortening")
            try check(result.requestedSharing == .privateAccess, "Private upload must retain its explicitly requested sharing policy")
            try check(trace.requests.count == 2 && trace.permissionRequests.isEmpty, "Private mode must never issue a sharing request")
            let initBody = try object(trace.requests[0])
            try check(initBody["name"] as? String == "Retina Screenshot.png", "Upload must use the requested filename")
            try check((initBody["parents"] as? [String]) == ["folder_fixture"], "Upload must target the chosen folder")
            try check(DriveMockTrace.body(trace.requests[1]) == imageBytes, "Resumable transfer must contain original encoded screenshot bytes")
            try check(trace.requests.allSatisfy { $0.url?.host == "www.googleapis.com" }, "No third-party shortener may be called")
        }
    }

    static func publicLink() async throws {
        try await withService { service, trace in
            trace.responder = { request in
                if request.url?.path.hasSuffix("/permissions") == true {
                    let permission = try object(request)
                    try check(permission["type"] as? String == "anyone" && permission["role"] as? String == "reader", "Public link permission must be read-only anyone access")
                    try check(permission["allowFileDiscovery"] as? Bool == false, "Public viewer link must be unlisted")
                    try check(request.url?.query?.contains("sendNotificationEmail") != true, "Anyone permission does not support email notifications parameter")
                    return .json(["id": "anyoneWithLink", "type": "anyone", "role": "reader"])
                }
                if request.httpMethod == "GET" { return metadata(url: refreshedViewer, publicAccess: true) }
                return try baseUploadResponder(request)
            }
            let result = try await service.uploadAndLink(data: imageBytes, name: "Screenshot.png", sharing: .anyoneWithLink)
            try check(result.isPublic && result.warning == nil, "Anyone link must be marked public only after permission confirmation")
            try check(result.requestedSharing == .anyoneWithLink, "Anyone link policy must survive later preference changes")
            try check(result.driveURL.absoluteString == refreshedViewer && result.shareURL == result.driveURL, "Use Google's post-sharing viewer link including resource key")
            try check(trace.uploadStarts == 1 && trace.uploadTransfers == 1 && trace.permissionRequests.count == 1, "Publishing must not upload a second file")
            try check(service.lastUploadResult == result && service.lastUploadedURL == result.shareURL, "Observable final result must match returned metadata")
        }
    }

    static func sharingFailureAndRetry() async throws {
        try await withService { service, trace in
            var refuseSharing = true
            trace.responder = { request in
                if request.url?.path.hasSuffix("/permissions") == true {
                    if refuseSharing { return .json(["error": ["message": "Workspace policy blocks public sharing"]], status: 403) }
                    return .json(["id": "anyoneWithLink", "type": "anyone", "role": "reader"])
                }
                if request.httpMethod == "GET" { return metadata(url: refreshedViewer, publicAccess: true) }
                return try baseUploadResponder(request)
            }
            let first = try await service.uploadAndLink(data: imageBytes, name: "Screenshot.png", sharing: .anyoneWithLink)
            try check(first.fileID == "file_fixture" && first.driveURL.absoluteString == viewer, "Sharing failure must retain uploaded file and original URL")
            try check(!first.isPublic && first.warning?.contains("Workspace policy") == true, "Sharing failure must return a clear warning without claiming public access")
            try check(first.requestedSharing == .anyoneWithLink, "Failed publication must retain its original requested policy for retry")
            try check(trace.uploadStarts == 1 && trace.uploadTransfers == 1, "Permission failure must not reupload")
            refuseSharing = false
            let retried = await service.publishLink(for: first, sharing: .anyoneWithLink)
            try check(retried.isPublic && retried.warning == nil, "Retry must publish the existing file")
            try check(trace.uploadStarts == 1 && trace.uploadTransfers == 1, "Link-only retry must never send image bytes again")
        }
    }

    static func linkRefreshFailure() async throws {
        try await withService { service, trace in
            var failMetadata = true
            trace.responder = { request in
                if request.url?.path.hasSuffix("/permissions") == true { return .json(["id": "anyoneWithLink", "type": "anyone", "role": "reader"]) }
                if request.httpMethod == "GET" {
                    if failMetadata { return .json(["error": ["message": "Metadata temporarily unavailable"]], status: 503) }
                    return metadata(url: refreshedViewer, publicAccess: true)
                }
                return try baseUploadResponder(request)
            }
            let result = try await service.uploadAndLink(data: imageBytes, name: "Screenshot.png", sharing: .anyoneWithLink)
            try check(result.isPublic && result.fileID == "file_fixture", "Metadata outage must not discard uploaded file or confirmed permission")
            try check(result.warning != nil && !result.hasVerifiedDriveURL, "A potentially stale resource key must be flagged, not described as ready")
            try check(trace.uploadStarts == 1 && trace.uploadTransfers == 1, "Metadata outage must never trigger reupload")
            failMetadata = false
            let retried = await service.publishLink(for: result, sharing: .anyoneWithLink)
            try check(retried.hasVerifiedDriveURL && retried.warning == nil && retried.driveURL.absoluteString == refreshedViewer, "Link refresh retry must recover Google's current viewer link")
            try check(trace.uploadStarts == 1 && trace.uploadTransfers == 1 && trace.permissionRequests.count == 1, "Link refresh retry must not duplicate uploads or permissions")
        }
    }

    static func inheritedAccess() async throws {
        try await withService { service, trace in
            trace.responder = { request in
                if request.httpMethod == "PUT" { return metadata(url: viewer, publicAccess: true) }
                return try baseUploadResponder(request)
            }
            let result = try await service.uploadAndLink(data: imageBytes, name: "Screenshot.png", sharing: .privateAccess)
            try check(result.isPublic, "Existing anyone permission inherited from folder must not be mislabeled private")
            try check(trace.permissionRequests.isEmpty, "Existing-access mode must not change inherited permissions")
        }
    }

    static func codableAndValidation() throws {
        let original = DriveUploadResult(fileID: "file_fixture", driveURL: URL(string: viewer)!, isPublic: true, warning: "Example", requestedSharing: .anyoneWithLink)
        let roundTrip = try JSONDecoder().decode(DriveUploadResult.self, from: JSONEncoder().encode(original))
        try check(roundTrip == original, "Upload metadata and requested sharing policy must survive persistence")
        let legacy = try JSONSerialization.data(withJSONObject: ["fileID": "older_file", "driveURL": viewer, "isPublic": false])
        let decodedLegacy = try JSONDecoder().decode(DriveUploadResult.self, from: legacy)
        try check(decodedLegacy.requestedSharing == .privateAccess, "Metadata without a stored policy must safely default to private access")
        try check(!DriveLinkValidation.isDriveViewerURL(URL(string: "https://drive.google.com.evil.example/file/d/a/view")!), "Lookalike Drive host must be rejected")
        try check(!DriveLinkValidation.isDriveViewerURL(URL(string: "http://drive.google.com/file/d/a/view")!), "Drive viewer URL must use HTTPS")
        try check(!DriveLinkValidation.isDriveViewerURL(URL(string: "https://user:secret@drive.google.com/file/d/a/view")!), "Viewer link must not contain credentials")
    }

    static func configurationReadiness() async throws {
        let suite = "SnapDrive-ConfigurationChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let previousArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(["drive.oauth.clientID": ""], forName: UserDefaults.argumentDomain)
        defer {
            defaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain)
            defaults.removePersistentDomain(forName: suite)
        }
        let service = DriveService(defaults: defaults, transientAccessToken: "fixture-configuration-token")
        try check(!service.hasOAuthConfiguration, "An empty client ID must require setup")
        service.clientID = " \n\t"
        try check(!service.hasOAuthConfiguration, "Whitespace must not make account setup appear complete")
        await service.connect()
        try check(!service.busy && service.status.contains("setup is required"), "Missing configuration must show a helpful setup state without starting sign-in")
        for invalid in [".apps.googleusercontent.com", "bad client.apps.googleusercontent.com", "https://123-abc.apps.googleusercontent.com", "123-abc.apps.googleusercontent.com.evil.example", "123-abc", "名.apps.googleusercontent.com"] {
            service.clientID = invalid
            try check(!service.hasOAuthConfiguration, "Malformed OAuth ID must not pass local readiness validation")
        }
        service.clientID = " 1234567890-test_client.apps.googleusercontent.com \n"
        try check(service.hasOAuthConfiguration, "Valid client ID should tolerate surrounding pasted whitespace")
        try check(service.clientSecret.isEmpty, "Desktop client secret is optional for local readiness")
    }

    static func fingerprints() throws {
        let suite = "SnapDrive-FingerprintChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // Override the outer folder smoke test's argument-domain client ID in memory.
        let previousArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        defaults.setVolatileDomain(["drive.oauth.clientID": "fixture-client-A"], forName: UserDefaults.argumentDomain)
        let first = DriveService(defaults: defaults, transientAccessToken: "fixture-token-A")
        let same = DriveService(defaults: defaults, transientAccessToken: "fixture-token-A")
        let changedToken = DriveService(defaults: defaults, transientAccessToken: "fixture-token-B")
        defaults.setVolatileDomain(["drive.oauth.clientID": "fixture-client-B"], forName: UserDefaults.argumentDomain)
        let changedClient = DriveService(defaults: defaults, transientAccessToken: "fixture-token-A")
        try check(first.connectionFingerprint.count == 64, "Queue marker must be a SHA256 digest")
        try check(first.connectionFingerprint == same.connectionFingerprint, "Same connection must have a stable queue marker")
        try check(first.connectionFingerprint != changedToken.connectionFingerprint, "New authorization token must change queue marker")
        try check(first.connectionFingerprint != changedClient.connectionFingerprint, "Client identity must be included in queue marker")
        try check(!first.connectionFingerprint.contains("fixture-token"), "Queue marker must never reveal raw credentials")
        first.clientID = "changed-after-init"
        try check(first.connectionFingerprint.isEmpty, "Disconnected service must not claim an active account marker")
    }

    static func baseUploadResponder(_ request: URLRequest) throws -> DriveMockReply {
        try check(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token-never-sent", "Google calls must carry the injected test token")
        if request.httpMethod == "POST" && request.url?.path == "/upload/drive/v3/files" {
            return DriveMockReply(status: 200, headers: ["Location": "https://www.googleapis.com/upload/drive/v3/files?upload_id=fixture"], data: Data())
        }
        if request.httpMethod == "PUT" { return metadata(url: viewer, publicAccess: false) }
        throw Failure("Unexpected request intercepted: \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
    }
    static func metadata(url: String, publicAccess: Bool) -> DriveMockReply {
        .json(["id": "file_fixture", "webViewLink": url, "permissions": publicAccess ? [["type": "anyone", "role": "reader"]] : [["type": "user", "role": "owner"]]])
    }
    static func object(_ request: URLRequest) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: DriveMockTrace.body(request)) as? [String: Any] ?? [:]
    }
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message) }
    }
    struct Failure: LocalizedError { var message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }
}

struct DriveMockReply {
    var status: Int
    var headers: [String: String]
    var data: Data
    static func json(_ object: [String: Any], status: Int = 200) -> DriveMockReply {
        DriveMockReply(status: status, headers: ["Content-Type": "application/json"], data: try! JSONSerialization.data(withJSONObject: object))
    }
}
final class DriveMockTrace {
    var responder: ((URLRequest) throws -> DriveMockReply)?
    private(set) var requests: [URLRequest] = []
    func reply(_ request: URLRequest) throws -> DriveMockReply {
        requests.append(request)
        guard let responder else { throw DriveLinkChecks.Failure("No mock responder installed") }
        return try responder(request)
    }
    var uploadStarts: Int { requests.filter { $0.httpMethod == "POST" && $0.url?.path == "/upload/drive/v3/files" }.count }
    var uploadTransfers: Int { requests.filter { $0.httpMethod == "PUT" }.count }
    var permissionRequests: [URLRequest] { requests.filter { $0.url?.path.hasSuffix("/permissions") == true } }
    static func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
private final class DriveMockProtocol: URLProtocol {
    static var trace: DriveMockTrace?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let trace = Self.trace else { throw DriveLinkChecks.Failure("Blocked unexpected network request") }
            let reply = try trace.reply(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
