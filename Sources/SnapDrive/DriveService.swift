import AppKit
import Combine
import CryptoKit
import Foundation
import Network
import Security
import UniformTypeIdentifiers

/// A desktop OAuth client: the app receives only access to files it creates.
@MainActor
final class DriveService: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var busy = false
    @Published var status = "Connect Google Drive or choose a synced folder."
    @Published private(set) var lastUploadedURL: URL?
    @Published private(set) var lastUploadResult: DriveUploadResult?
    @Published var clientID: String {
        didSet {
            settings.set(clientID, forKey: "drive.oauth.clientID")
            if oldValue != clientID { isConnected = false; token = nil; folderID = "" }
        }
    }
    @Published var clientSecret: String {
        didSet {
            do { try DriveKeychain.set(clientSecret, account: "clientSecret") }
            catch { status = error.localizedDescription }
        }
    }
    @Published var folderID: String { didSet { settings.set(folderID, forKey: "drive.folderID") } }
    @Published var autoUpload: Bool { didSet { settings.set(autoUpload, forKey: "drive.autoUpload") } }
    @Published var syncFolder: String { didSet { settings.set(syncFolder, forKey: "drive.syncFolder") } }

    /// Local readiness only: Google still validates the client, project, and consent in the browser.
    /// A Desktop OAuth secret is optional; the client ID is required.
    var hasOAuthConfiguration: Bool { Self.normalizedOAuthClientID(clientID) != nil }

    private static func normalizedOAuthClientID(_ value: String) -> String? {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = ".apps.googleusercontent.com"
        guard id.hasSuffix(suffix) else { return nil }
        let prefix = id.dropLast(suffix.count)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard !prefix.isEmpty, prefix.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return id
    }

    /// A non-reversible local marker for queue ownership; never exposes an OAuth credential.
    /// Reauthorization may change it, which deliberately pauses old jobs for explicit review.
    var connectionFingerprint: String {
        guard isConnected, let token else { return "" }
        let identity = token.refreshToken.isEmpty ? "access:" + token.accessToken : "refresh:" + token.refreshToken
        let material = "SnapDrive-connection-v1\n" + clientID + "\n" + identity
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private var token: StoredDriveToken?
    private var authFlow: DriveOAuthLoopback?
    private let session: URLSession
    private let settings: UserDefaults
    private let persistentCredentials: Bool
    private var tokenAccount: String { "token." + SHA256.hash(data: Data(clientID.utf8)).map { String(format: "%02x", $0) }.joined() }

    /// Session/token injection is used by local protocol tests; transient tokens never touch Keychain.
    init(session injectedSession: URLSession? = nil, defaults: UserDefaults = .standard, transientAccessToken: String? = nil, registeredClientID: String? = nil) {
        self.settings = defaults
        persistentCredentials = transientAccessToken == nil
        let configuredID = defaults.string(forKey: "drive.oauth.clientID") ?? ""
        let savedClientID = configuredID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (registeredClientID ?? GoogleAppConfiguration.clientID ?? "") : configuredID
        clientID = savedClientID
        clientSecret = savedClientID.isEmpty || transientAccessToken != nil ? "" : ((try? DriveKeychain.get(account: "clientSecret")) ?? (savedClientID == GoogleAppConfiguration.clientID ? GoogleAppConfiguration.clientSecret : ""))
        folderID = defaults.string(forKey: "drive.folderID") ?? ""
        autoUpload = defaults.bool(forKey: "drive.autoUpload")
        syncFolder = defaults.string(forKey: "drive.syncFolder") ?? ""
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        session = injectedSession ?? URLSession(configuration: config)
        if let access = transientAccessToken {
            token = StoredDriveToken(accessToken: access, refreshToken: "", expiresAt: Date().addingTimeInterval(3600))
            isConnected = true
        } else if !savedClientID.isEmpty, let saved = try? DriveKeychain.get(account: tokenAccount), let data = saved.data(using: .utf8),
           let stored = try? JSONDecoder().decode(StoredDriveToken.self, from: data) {
            token = stored
            isConnected = !stored.refreshToken.isEmpty || stored.expiresAt > Date()
            if isConnected { status = "Google Drive connected" }
        }
    }

    /// Import the JSON downloaded for a Google Cloud Desktop app OAuth client.
    func importCredentials() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose the OAuth client JSON downloaded from Google Cloud (Desktop app)."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.importCredentials(from: url)
        }
    }

    private func importCredentials(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let installed = json?["installed"] as? [String: Any],
                  let rawID = installed["client_id"] as? String, let id = Self.normalizedOAuthClientID(rawID) else {
                throw DriveServiceError.message("Choose a Desktop app OAuth JSON file. Web and service-account credentials are not supported.")
            }
            clientID = id
            clientSecret = installed["client_secret"] as? String ?? ""
            status = "Desktop OAuth credentials imported. Click Connect Google Drive."
        } catch { status = error.localizedDescription }
    }

    func connect() async {
        guard !busy else { return }
        guard hasOAuthConfiguration else {
            status = clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Google account setup is required. Import your Desktop OAuth JSON to enable browser sign-in, or use a synced Drive folder without account setup."
                : "This OAuth client ID is not valid. Import the Desktop app JSON downloaded from Google Cloud."
            return
        }
        busy = true
        defer { busy = false; authFlow = nil }
        do {
            let verifier = try randomURLSafe(count: 32)
            let state = try randomURLSafe(count: 32)
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
            let flow = DriveOAuthLoopback(expectedState: state)
            authFlow = flow
            let redirect = try await flow.start()
            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID.trimmingCharacters(in: .whitespacesAndNewlines)),
                URLQueryItem(name: "redirect_uri", value: redirect.absoluteString),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.file"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent select_account"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256")
            ]
            status = "Finish signing in in your browser. You can cancel here."
            guard let url = components.url, NSWorkspace.shared.open(url) else {
                flow.cancel()
                throw DriveServiceError.message("Could not open the sign-in browser.")
            }
            let callback = try await flow.waitForCallback()
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.first(where: { $0.name == "state" })?.value == state else {
                throw DriveServiceError.message("The sign-in response could not be verified. Please connect again.")
            }
            if let error = items.first(where: { $0.name == "error" })?.value {
                throw DriveServiceError.message(error == "access_denied" ? "Google Drive sign-in was cancelled." : "Google sign-in failed: \(error)")
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                throw DriveServiceError.message("Google did not return an authorization code.")
            }
            let response = try await requestTokens(fields: ["code": code, "code_verifier": verifier,
                "grant_type": "authorization_code", "redirect_uri": redirect.absoluteString])
            try store(response, previousRefreshToken: "")
            // The account chooser may return a different account. A folder created
            // for the previous account must never be reused with these new tokens.
            folderID = ""; lastUploadedURL = nil; lastUploadResult = nil
            isConnected = true
            status = "Google Drive connected. New uploads use the sharing option selected in SnapDrive."
        } catch {
            status = error.localizedDescription
        }
    }

    func cancelConnection() { authFlow?.cancel() }

    /// Disconnects locally. Google Account permissions can also be revoked in Account settings.
    func disconnect() {
        authFlow?.cancel()
        var keychainError: Error?
        do { try DriveKeychain.delete(account: tokenAccount) } catch { keychainError = error }
        token = nil
        isConnected = false
        lastUploadedURL = nil
        lastUploadResult = nil
        folderID = ""
        if let keychainError {
            status = "Disconnected in this session, but saved credentials could not be removed. \(keychainError.localizedDescription)"
        } else {
            status = "Google Drive disconnected on this Mac."
        }
    }

    /// Compatibility API: uploads once and keeps existing Drive access.
    func upload(data: Data, name: String) async throws -> URL {
        try await uploadFile(data: data, name: name).driveURL
    }

    func uploadAndLink(data: Data, name: String, sharing: DriveSharing = .privateAccess) async throws -> DriveUploadResult {
        let uploaded = try await uploadFile(data: data, name: name)
        return await publishLink(for: uploaded, sharing: sharing)
    }

    /// Upload only. A returned result means the file exists; retain it before retrying link publication.
    func uploadFile(data: Data, name: String) async throws -> DriveUploadResult {
        guard !busy else { throw DriveServiceError.message("A Google Drive operation is already in progress.") }
        guard isConnected else { throw DriveServiceError.message("Connect Google Drive before uploading.") }
        guard !data.isEmpty else { throw DriveServiceError.message("The screenshot is empty.") }
        busy = true
        defer { busy = false }
        do {
            status = "Uploading screenshot to Google Drive…"
            let folder = try await destinationFolder()
            let metadata: [String: Any] = ["name": name, "parents": [folder]]
            var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,webViewLink,resourceKey,permissions(type,role)&supportsAllDrives=true")!)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue(mimeType(for: name), forHTTPHeaderField: "X-Upload-Content-Type")
            request.setValue(String(data.count), forHTTPHeaderField: "X-Upload-Content-Length")
            request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
            let (_, response) = try await authorized(request)
            guard let location = response.value(forHTTPHeaderField: "Location"), let uploadURL = URL(string: location),
                  uploadURL.scheme == "https", let host = uploadURL.host,
                  host == "www.googleapis.com" || host == "content.googleapis.com" else {
                throw DriveServiceError.message("Google Drive did not return a valid upload session.")
            }
            var transfer = URLRequest(url: uploadURL)
            transfer.httpMethod = "PUT"
            transfer.timeoutInterval = 120
            transfer.setValue(mimeType(for: name), forHTTPHeaderField: "Content-Type")
            transfer.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
            transfer.httpBody = data
            let (bytes, _) = try await authorized(transfer)
            let file = try JSONDecoder().decode(DriveCreatedFile.self, from: bytes)
            var result = try makeResult(file)
            if !result.hasVerifiedDriveURL {
                // Metadata may become available after creation. This does not upload the image again.
                if let refreshed = try? await fileMetadata(id: file.id) { result = try makeResult(refreshed) }
            }
            lastUploadResult = result
            lastUploadedURL = result.driveURL
            status = "Uploaded to Google Drive. Existing folder permissions still apply."
            return result
        } catch {
            status = "Upload failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Share a previously uploaded file. Failures retain its original link and never reupload.
    func publishLink(for original: DriveUploadResult, sharing: DriveSharing = .privateAccess) async -> DriveUploadResult {
        var result = original
        result.requestedSharing = sharing
        var warnings: [String] = []
        var needsLinkRefresh = !original.hasVerifiedDriveURL
        guard !busy else {
            result.warning = "The screenshot is uploaded. Another Drive operation is in progress; retry its link later."
            return result
        }
        busy = true
        defer { busy = false }
        if sharing == .anyoneWithLink && !result.isPublic {
            do {
                guard !result.fileID.isEmpty else { throw DriveServiceError.message("The uploaded file ID is missing.") }
                status = "Allowing read-only access for anyone with the link…"
                let endpoint = URL(string: "https://www.googleapis.com/drive/v3/files")!.appendingPathComponent(result.fileID).appendingPathComponent("permissions")
                var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "supportsAllDrives", value: "true"), URLQueryItem(name: "fields", value: "id,type,role")]
                var request = URLRequest(url: components.url!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["type": "anyone", "role": "reader", "allowFileDiscovery": false])
                let (bytes, _) = try await authorized(request)
                let permission = try JSONDecoder().decode(DrivePermission.self, from: bytes)
                guard permission.type == "anyone", permission.role == "reader" else {
                    throw DriveServiceError.message("Google did not confirm the requested read-only link permission.")
                }
                result.isPublic = true
                // Google may issue a resource key when link access is enabled.
                needsLinkRefresh = true
            } catch {
                warnings.append("The screenshot uploaded, but anyone-with-link sharing was not confirmed. Existing Drive access still applies. \(error.localizedDescription)")
            }
        }
        if needsLinkRefresh {
            do {
                let refreshed = try await fileMetadata(id: result.fileID)
                let link = try makeResult(refreshed)
                guard link.hasVerifiedDriveURL else { throw DriveServiceError.message("Google omitted the viewer link.") }
                result.driveURL = link.driveURL
                result.shareURL = link.driveURL
                result.shortened = false
                result.hasVerifiedDriveURL = true
            } catch {
                result.hasVerifiedDriveURL = false
                result.shortened = false
                result.shareURL = result.driveURL
                warnings.append("The screenshot is uploaded, but its current viewer link could not be refreshed. Open the file in Drive to copy its link. \(error.localizedDescription)")
            }
        }
        result.warning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        lastUploadResult = result
        lastUploadedURL = result.shareURL
        status = result.warning == nil ? "Uploaded · Drive link ready" : "Uploaded · Link needs attention"
        return result
    }

    private func fileMetadata(id: String) async throws -> DriveCreatedFile {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files")!.appendingPathComponent(id)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: "id,webViewLink,resourceKey,permissions(type,role)"), URLQueryItem(name: "supportsAllDrives", value: "true")]
        let (data, _) = try await authorized(URLRequest(url: components.url!))
        return try JSONDecoder().decode(DriveCreatedFile.self, from: data)
    }

    private func makeResult(_ file: DriveCreatedFile) throws -> DriveUploadResult {
        guard !file.id.isEmpty, !file.id.contains("/"), file.id != ".", file.id != ".." else {
            throw DriveServiceError.message("Google returned an invalid uploaded file ID.")
        }
        let isPublic = file.permissions?.contains(where: { $0.type == "anyone" }) ?? false
        if let raw = file.webViewLink, let url = URL(string: raw), DriveLinkValidation.isDriveViewerURL(url) {
            // Preserve Google's full webViewLink, including its resourcekey query parameter.
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            if let key = file.resourceKey, !key.isEmpty, !(components.queryItems ?? []).contains(where: { $0.name.lowercased() == "resourcekey" }) {
                var items = components.queryItems ?? []; items.append(URLQueryItem(name: "resourcekey", value: key)); components.queryItems = items
            }
            return DriveUploadResult(fileID: file.id, driveURL: components.url ?? url, isPublic: isPublic)
        }
        var components = URLComponents(url: URL(string: "https://drive.google.com/file/d/")!.appendingPathComponent(file.id).appendingPathComponent("view"), resolvingAgainstBaseURL: false)!
        if let key = file.resourceKey, !key.isEmpty { components.queryItems = [URLQueryItem(name: "resourcekey", value: key)] }
        return DriveUploadResult(fileID: file.id, driveURL: components.url!, isPublic: isPublic,
            warning: "The screenshot uploaded, but Google did not return its viewer link. Open the file in Google Drive to copy its link.", hasVerifiedDriveURL: false)
    }

    /// Returns existing Drive for desktop roots without selecting one or granting access.
    static func discoverDriveFolders() -> [URL] {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let cloud = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        var candidates = ((try? manager.contentsOfDirectory(at: cloud, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("GoogleDrive-") }
            .map { root -> URL in
                let myDrive = root.appendingPathComponent("My Drive", isDirectory: true)
                return manager.fileExists(atPath: myDrive.path) ? myDrive : root
            }
        let legacy = home.appendingPathComponent("Google Drive", isDirectory: true)
        if manager.fileExists(atPath: legacy.path) { candidates.append(legacy) }
        return candidates.sorted { $0.path < $1.path }
    }

    func chooseSyncFolder(onSelection: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose a folder inside Google Drive for desktop. Google Drive will handle syncing."
        panel.prompt = "Choose folder"
        panel.directoryURL = syncFolder.isEmpty ? Self.discoverDriveFolders().first : URL(fileURLWithPath: syncFolder, isDirectory: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.syncFolder = url.path
            self.status = "Synced-folder destination selected. Google Drive for desktop handles uploading."
            onSelection?()
        }
    }

    func saveToSyncFolder(data: Data, name: String) throws -> URL {
        guard !syncFolder.isEmpty else { throw DriveServiceError.message("Choose a Google Drive synced folder first.") }
        let expandedPath = (syncFolder.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        let folder = URL(fileURLWithPath: expandedPath, isDirectory: true)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &directory), directory.boolValue else {
            throw DriveServiceError.message("The synced folder is unavailable. Open Google Drive for desktop or choose the folder again.")
        }
        let safeName = URL(fileURLWithPath: name).lastPathComponent
        var destination = folder.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: destination.path) {
            let base = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            destination = folder.appendingPathComponent(base + "-" + String(UUID().uuidString.prefix(8))).appendingPathExtension(ext)
        }
        // Exclusive creation protects an existing screenshot even if another save wins a race.
        try data.write(to: destination, options: .withoutOverwriting)
        status = "Saved to synced folder. Google Drive for desktop manages upload progress."
        return destination
    }

    private func destinationFolder() async throws -> String {
        if !folderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return folderID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Find the app's folder before creating one, including after reconnecting.
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [URLQueryItem(name: "q", value: "trashed = false and mimeType = 'application/vnd.google-apps.folder' and appProperties has { key='snapdrive' and value='screenshots' }"), URLQueryItem(name: "fields", value: "files(id)"), URLQueryItem(name: "pageSize", value: "1")]
        let (listing, _) = try await authorized(URLRequest(url: components.url!))
        if let existing = try JSONDecoder().decode(DriveFileList.self, from: listing).files.first {
            folderID = existing.id
            return existing.id
        }
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": "SnapDrive Screenshots", "mimeType": "application/vnd.google-apps.folder", "appProperties": ["snapdrive": "screenshots"]])
        let (data, _) = try await authorized(request)
        let folder = try JSONDecoder().decode(DriveCreatedFile.self, from: data)
        folderID = folder.id
        return folder.id
    }

    private func authorized(_ request: URLRequest, retry: Bool = true) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DriveServiceError.message("Invalid response from Google Drive.") }
        if http.statusCode == 401, retry, let current = token, !current.refreshToken.isEmpty {
            let refreshed = try await requestTokens(fields: ["grant_type": "refresh_token", "refresh_token": current.refreshToken])
            try store(refreshed, previousRefreshToken: current.refreshToken)
            return try await authorized(request, retry: false)
        }
        guard (200...299).contains(http.statusCode) else { throw googleError(data, code: http.statusCode) }
        return (data, http)
    }

    private func accessToken() async throws -> String {
        guard let current = token else { isConnected = false; throw DriveServiceError.message("Connect Google Drive first.") }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        guard !current.refreshToken.isEmpty else { isConnected = false; throw DriveServiceError.message("Your Google session expired. Connect Google Drive again.") }
        let response = try await requestTokens(fields: ["grant_type": "refresh_token", "refresh_token": current.refreshToken])
        try store(response, previousRefreshToken: current.refreshToken)
        return response.access_token
    }

    private func requestTokens(fields: [String: String]) async throws -> DriveTokenResponse {
        var fields = fields
        fields["client_id"] = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clientSecret.isEmpty { fields["client_secret"] = clientSecret }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = fields.sorted(by: { $0.key < $1.key }).map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DriveServiceError.message("Invalid response from Google sign-in.") }
        guard (200...299).contains(http.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["error"] as? String == "invalid_grant" {
                isConnected = false
                throw DriveServiceError.message("Google authorization expired or was revoked. Connect Google Drive again.")
            }
            throw googleError(data, code: http.statusCode)
        }
        return try JSONDecoder().decode(DriveTokenResponse.self, from: data)
    }

    private func store(_ response: DriveTokenResponse, previousRefreshToken: String) throws {
        let stored = StoredDriveToken(accessToken: response.access_token, refreshToken: response.refresh_token ?? previousRefreshToken,
                                      expiresAt: Date().addingTimeInterval(response.expires_in))
        let data = try JSONEncoder().encode(stored)
        if persistentCredentials { try DriveKeychain.set(String(decoding: data, as: UTF8.self), account: tokenAccount) }
        token = stored
    }

    private func googleError(_ data: Data, code: Int) -> Error {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                return DriveServiceError.message("Google Drive (\(code)): \(message)")
            }
            if let message = json["error_description"] as? String { return DriveServiceError.message("Google sign-in: \(message)") }
        }
        return DriveServiceError.message("Google Drive returned error \(code). Check your connection, Drive permissions, and available storage.")
    }

    private func mimeType(for name: String) -> String {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        default: return "image/png"
        }
    }

    private func randomURLSafe(count: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw DriveServiceError.message("Could not create a secure sign-in request.")
        }
        return Data(bytes).base64URLEncoded
    }
}

private struct StoredDriveToken: Codable { let accessToken: String; let refreshToken: String; let expiresAt: Date }
private struct DriveTokenResponse: Decodable { let access_token: String; let refresh_token: String?; let expires_in: TimeInterval }
private struct DriveCreatedFile: Decodable { let id: String; let webViewLink: String?; let resourceKey: String?; let permissions: [DrivePermission]? }
private struct DrivePermission: Decodable { let type: String?; let role: String? }
private struct DriveFileList: Decodable { let files: [DriveCreatedFile] }
private enum DriveServiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
private extension Data {
    var base64URLEncoded: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

private enum DriveKeychain {
    static let service = "com.snapdrive.desktop.google-drive"
    static func get(account: String) throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return String(data: data, encoding: .utf8)
    }
    static func set(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let update: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let result = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if result == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = Data(value.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if result != errSecSuccess { throw failure(result) }
    }
    static func delete(account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw failure(result) }
    }
    private static func failure(_ status: OSStatus) -> Error {
        DriveServiceError.message("Keychain could not store or retrieve Google credentials (\(status)). Allow SnapDrive to access its Keychain items and try again.")
    }
}

/// A small transport seam lets callback lifetime be checked without real sockets or Google calls.
enum DriveLoopbackListenerState {
    case ready(UInt16)
    case failed(Error)
    case cancelled
}
protocol DriveLoopbackListening: AnyObject {
    var stateUpdateHandler: ((DriveLoopbackListenerState) -> Void)? { get set }
    var newConnectionHandler: ((NWConnection) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func cancel()
}
private final class DriveSystemLoopbackListener: DriveLoopbackListening {
    var stateUpdateHandler: ((DriveLoopbackListenerState) -> Void)?
    var newConnectionHandler: ((NWConnection) -> Void)?
    private let listener: NWListener
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let port = self.listener.port { self.stateUpdateHandler?(.ready(port.rawValue)) }
                else { self.stateUpdateHandler?(.failed(DriveServiceError.message("The local sign-in listener has no assigned port."))) }
            case .failed(let error): self.stateUpdateHandler?(.failed(error))
            case .cancelled: self.stateUpdateHandler?(.cancelled)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let handler = self?.newConnectionHandler else { connection.cancel(); return }
            handler(connection)
        }
    }
    func start(queue: DispatchQueue) { listener.start(queue: queue) }
    func cancel() { listener.stateUpdateHandler = nil; listener.newConnectionHandler = nil; listener.cancel() }
}

/// Reject unrelated/local forged requests without consuming the real OAuth response.
enum DriveOAuthCallbackValidator {
    static func callbackURL(requestLine: String, redirect: URL, expectedState: String) -> URL? {
        let pieces = requestLine.split(separator: " ")
        guard pieces.count == 3, pieces[0] == "GET", pieces[2].hasPrefix("HTTP/1."), !expectedState.isEmpty,
              let target = URLComponents(string: String(pieces[1])), target.scheme == nil, target.host == nil,
              target.fragment == nil, target.path == "/oauth2callback" else { return nil }
        let items = target.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        let codes = items.filter { $0.name == "code" }
        let errors = items.filter { $0.name == "error" }
        guard states.count == 1, states.first?.value == expectedState else { return nil }
        let hasCode = codes.count == 1 && !(codes.first?.value ?? "").isEmpty && errors.isEmpty
        let hasError = errors.count == 1 && !(errors.first?.value ?? "").isEmpty && codes.isEmpty
        guard hasCode || hasError, let url = URL(string: String(pieces[1]), relativeTo: redirect)?.absoluteURL,
              url.scheme == redirect.scheme, url.host == redirect.host, url.port == redirect.port else { return nil }
        return url
    }
}

/// Only listens on IPv4 loopback; it never exposes the OAuth callback to the network.
@MainActor
final class DriveOAuthLoopback {
    private var listener: DriveLoopbackListening?
    private var readyContinuation: CheckedContinuation<URL, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var callbackResult: Result<URL, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var redirect: URL?
    private var finished = false
    private var started = false
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.snapdrive.oauth-loopback")
    private let expectedState: String
    private let timeoutNanoseconds: UInt64
    private let listenerFactory: () throws -> DriveLoopbackListening

    init(expectedState: String, timeoutNanoseconds: UInt64 = 180_000_000_000,
         listenerFactory: @escaping () throws -> DriveLoopbackListening = { try DriveSystemLoopbackListener() }) {
        self.expectedState = expectedState
        self.timeoutNanoseconds = timeoutNanoseconds
        self.listenerFactory = listenerFactory
    }

    func start() async throws -> URL {
        guard !started, !finished, !Task.isCancelled else { throw DriveServiceError.message("Google Drive sign-in was cancelled or has already started.") }
        started = true
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                readyContinuation = continuation
                // Cover startup/waiting as well as the browser's consent round trip.
                timeoutTask = Task { [weak self, timeoutNanoseconds] in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(DriveServiceError.message("Google sign-in timed out. Click Connect Google Drive to try again.")))
                }
                do {
                    let listener = try listenerFactory()
                    self.listener = listener
                    listener.stateUpdateHandler = { [weak self] state in
                        Task { @MainActor in
                            guard let self, !self.finished else { return }
                            switch state {
                            case .ready(let port):
                                guard self.redirect == nil else { return }
                                guard port > 0, let url = URL(string: "http://127.0.0.1:\(port)/oauth2callback") else {
                                    self.finish(.failure(DriveServiceError.message("Could not start the local sign-in callback.")))
                                    return
                                }
                                self.redirect = url
                                self.readyContinuation?.resume(returning: url)
                                self.readyContinuation = nil
                            case .failed(let error): self.finish(.failure(error))
                            case .cancelled: self.cancel()
                            }
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in
                        Task { @MainActor in
                            guard let self else { connection.cancel(); return }
                            self.accept(connection)
                        }
                    }
                    listener.start(queue: queue)
                } catch { finish(.failure(error)) }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
    }

    func waitForCallback() async throws -> URL {
        if let result = callbackResult { return try result.get() }
        guard started else { throw DriveServiceError.message("The local sign-in callback has not started.") }
        guard callbackContinuation == nil else { throw DriveServiceError.message("A sign-in callback is already being awaited.") }
        guard !Task.isCancelled else { cancel(); throw DriveServiceError.message("Google Drive sign-in was cancelled.") }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { callbackContinuation = $0 }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
    }

    func cancel() { finish(.failure(DriveServiceError.message("Google Drive sign-in was cancelled."))) }

    private func accept(_ connection: NWConnection) {
        guard !finished else { connection.cancel(); return }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
    }

    private func close(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.finished else { connection.cancel(); return }
                var bytes = accumulated
                if let data { bytes.append(data) }
                if bytes.count > 16384 || error != nil { self.close(connection); return }
                guard let text = String(data: bytes, encoding: .utf8), text.contains("\r\n\r\n") else {
                    if !complete { self.receive(connection, accumulated: bytes) } else { self.close(connection) }
                    return
                }
                let requestLine = text.components(separatedBy: "\r\n")[0]
                let handled = self.handleCallbackRequestLine(requestLine) { _ in
                    self.respond(connection, code: "200 OK", message: "Sign-in response received. Return to SnapDrive; you can close this tab.")
                }
                if !handled { self.respond(connection, code: "404 Not Found", message: "Return to SnapDrive to continue signing in.") }
            }
        }
    }

    /// Kept separate from socket reads so a fake transport can exercise continuation ordering.
    @discardableResult
    func handleCallbackRequestLine(_ line: String, beforeCompletion: (URL) -> Void = { _ in }) -> Bool {
        guard !finished, let redirect,
              let url = DriveOAuthCallbackValidator.callbackURL(requestLine: line, redirect: redirect, expectedState: expectedState) else { return false }
        beforeCompletion(url)
        finish(.success(url))
        return true
    }

    private func respond(_ connection: NWConnection, code: String, message: String) {
        // This small response owns its connection until buffered data is sent; other clients close in finish().
        connections.removeValue(forKey: ObjectIdentifier(connection))
        let body = "<!doctype html><html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>SnapDrive</title><body style=\"font:18px -apple-system,sans-serif;max-width:560px;margin:15vh auto;padding:28px\"><h1>SnapDrive</h1><p>\(message)</p></body></html>"
        let response = "HTTP/1.1 \(code)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        callbackResult = result
        timeoutTask?.cancel()
        timeoutTask = nil
        if let readyContinuation {
            self.readyContinuation = nil
            readyContinuation.resume(with: result)
        }
        callbackContinuation?.resume(with: result)
        callbackContinuation = nil
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }
}
