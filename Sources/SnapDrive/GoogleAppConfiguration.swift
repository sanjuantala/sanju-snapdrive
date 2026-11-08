import Foundation

/// Public OAuth application identity, registered once by the app publisher.
/// This contains no user's Google password, access token, or refresh token.
enum GoogleAppConfiguration {
    static var clientSecret: String {
        guard let url = Bundle.main.url(forResource: "GoogleOAuthPrivate", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else { return "" }
        return values["ClientSecret"] ?? ""
    }
    static var clientID: String? {
        guard let url = Bundle.main.url(forResource: "GoogleOAuthClient", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else { return nil }
        return values["ClientID"]
    }
}
