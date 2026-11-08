import SwiftUI
import AppKit

struct UploadResultView: View {
    @EnvironmentObject var model: EditorModel
    @EnvironmentObject var drive: DriveService
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack { Label("Screenshot uploaded", systemImage: "checkmark.icloud.fill").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            if let result = model.uploadResult {
                Label(result.isPublic ? "Anyone with this link can view" : "Your existing Drive access applies", systemImage: result.isPublic ? "globe" : "lock").foregroundStyle(result.isPublic ? .green : .secondary)
                Text(result.shareURL.absoluteString).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                if let warning = result.warning { Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                Text("This link points to the last uploaded version. Upload again after editing. This is the original Google Drive viewer link. It opens the full-quality exported image; no link-shortening service is used.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(model.toast == "Drive link copied" ? "Copied ✓" : "Copy link") { model.copyUploadLink() }.buttonStyle(.borderedProminent).disabled(!result.hasVerifiedDriveURL)
                    Button("Open in Drive") { NSWorkspace.shared.open(result.driveURL) }
                    Spacer()
                    if result.warning != nil { Button("Retry link sharing") { model.retryLinkPublishing(drive) }.disabled(model.busy || !drive.isConnected) }
                }
            } else { Text("Upload a screenshot to get its Drive link.").foregroundStyle(.secondary) }
        }.padding(28).frame(width: 570).preferredColorScheme(.dark)
    }
}
