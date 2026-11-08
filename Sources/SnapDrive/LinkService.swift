import Foundation

enum DriveSharing: String, Codable, CaseIterable, Identifiable {
    /// Preserve the destination folder's existing access; never adds a public permission.
    case privateAccess
    /// Adds an unlisted, read-only permission for anyone who has the link.
    case anyoneWithLink
    var id: String { rawValue }
    var title: String { self == .anyoneWithLink ? "Anyone with the link" : "Existing Drive access" }
}

/// Saved separately from image bytes so link publication can be retried without uploading again.
struct DriveUploadResult: Codable, Equatable {
    var fileID: String
    var driveURL: URL
    var shareURL: URL
    /// True when an anyone permission was confirmed; false does not override inherited folder access.
    var isPublic: Bool
    var shortened: Bool
    var warning: String?
    /// The sharing policy explicitly requested for this upload, independent of later defaults.
    var requestedSharing: DriveSharing
    /// False when the current Google viewer link could not be verified; the uploaded file is still retained.
    var hasVerifiedDriveURL: Bool

    init(fileID: String, driveURL: URL, shareURL: URL? = nil, isPublic: Bool = false,
         shortened: Bool = false, warning: String? = nil, hasVerifiedDriveURL: Bool = true, requestedSharing: DriveSharing = .privateAccess) {
        self.fileID = fileID
        self.driveURL = driveURL
        self.shareURL = shareURL ?? driveURL
        self.isPublic = isPublic
        self.shortened = shortened
        self.warning = warning
        self.requestedSharing = requestedSharing
        self.hasVerifiedDriveURL = hasVerifiedDriveURL
    }

    private enum CodingKeys: String, CodingKey { case fileID, driveURL, shareURL, isPublic, shortened, warning, hasVerifiedDriveURL, requestedSharing }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fileID = try values.decode(String.self, forKey: .fileID)
        driveURL = try values.decode(URL.self, forKey: .driveURL)
        shareURL = try values.decodeIfPresent(URL.self, forKey: .shareURL) ?? driveURL
        isPublic = try values.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        shortened = try values.decodeIfPresent(Bool.self, forKey: .shortened) ?? false
        warning = try values.decodeIfPresent(String.self, forKey: .warning)
        requestedSharing = try values.decodeIfPresent(DriveSharing.self, forKey: .requestedSharing) ?? .privateAccess
        hasVerifiedDriveURL = try values.decodeIfPresent(Bool.self, forKey: .hasVerifiedDriveURL) ?? true
    }
}

/// Keep complete Drive viewer URLs, including resourcekey query parameters.
enum DriveLinkValidation {
    static func isDriveViewerURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              host == "drive.google.com" || host == "docs.google.com", url.user == nil, url.password == nil,
              url.port == nil else { return false }
        return !url.path.isEmpty
    }
}
