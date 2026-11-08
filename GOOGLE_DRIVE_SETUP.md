# Optional Google Drive setup

Screenshot capture, editing, local history, and export work without Google Drive. Automatic uploads are off by default.

## Save through Drive for desktop

1. Install and sign in to [Google Drive for desktop](https://www.google.com/drive/download/).
2. Open **Drive settings** in SnapDrive and choose **Drive folder**.
3. Click **Choose folder…** and select a folder inside your local Google Drive.
4. Use **Save to Drive** when you want to save there.

SnapDrive saves the file locally. Drive for desktop handles syncing. Folder saves do not return a confirmed cloud share link. An ordinary local folder is also supported.

## Direct uploads

The public release does not include the author's Google account connection or a preconfigured OAuth client. Direct sign-in requires a publisher-configured build. Public sign-in setup is deferred; use a synced folder or local export in the standard release.

A configured build can upload the edited image and copy Google's viewer link. **Anyone with the link** adds read-only link access; **Existing Drive access** adds no public permission. Failed sharing can be retried without uploading another copy. The selected exported bytes are sent without recompression.

## Advanced source configuration

For a build with direct uploads:

1. Register a Google Cloud **Desktop app** OAuth client and enable the Drive API for its project.
2. Add its public client ID as the `ClientID` string in `Resources/GoogleOAuthClient.plist`.
3. If the registration requires a client secret, create a private plist containing a `ClientSecret` string. Pass its local path through `SNAPDRIVE_OAUTH_PRIVATE_PLIST` when building.
4. Configure the Google project's audience and approved users as required before signing in.

Keep private configuration out of Git and release source archives. Access and refresh tokens are stored in macOS Keychain, never in this repository. Changes to a Google registration do not affect local capture or editing.

See Google's official [native OAuth documentation](https://developers.google.com/identity/protocols/oauth2/native-app), [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), and [sharing permissions](https://developers.google.com/workspace/drive/api/guides/manage-sharing).
