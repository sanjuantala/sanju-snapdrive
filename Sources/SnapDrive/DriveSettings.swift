import SwiftUI
import Carbon

struct DriveSettings: View {
    @EnvironmentObject var drive: DriveService
    @EnvironmentObject var model: EditorModel
    @EnvironmentObject var capture: CaptureService
    @Environment(\.dismiss) var dismiss
    @ViewState private var advanced = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Label("Google Drive & capture", systemImage: "externaldrive.badge.icloud").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Save & upload behavior").font(.headline)
                        Toggle("Automatically send new images to Google Drive", isOn: $drive.autoUpload)
                        Text(drive.autoUpload ? "New captures and imports are sent immediately to the destination below. Turn this off to edit locally before uploading." : "Captures stay in local history. Upload only when you click Upload & copy link or explicitly choose Save to Drive.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Picker("Drive destination", selection: $model.driveMode) { Text("Drive folder").tag("folder"); Text("Upload & get link").tag("api") }.pickerStyle(.segmented)
                    if model.driveMode == "folder" {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Save through Google Drive for desktop").font(.headline)
                            Text("Choose a folder inside Google Drive. Local saves sync through Drive for desktop; a confirmed share link needs a direct upload.").font(.caption).foregroundStyle(.secondary)
                            HStack { Image(systemName: "folder.fill").foregroundStyle(.purple); Text(drive.syncFolder.isEmpty ? "No folder selected" : drive.syncFolder).font(.caption).textSelection(.enabled).lineLimit(3); Spacer(); Button("Choose folder…") { drive.chooseSyncFolder() } }.padding(12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            TextField("Or paste the full Google Drive folder path", text: $drive.syncFolder).textFieldStyle(.roundedBorder).font(.caption)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Google sign-in").font(.headline); Spacer(); Label(drive.isConnected ? "Connected" : "Not connected", systemImage: drive.isConnected ? "checkmark.circle.fill" : "circle").font(.caption).foregroundStyle(drive.isConnected ? .green : .secondary) }
                        Text("Upload the exported image at its selected resolution, then copy its original Drive link. Screenshot bytes are sent unchanged.").font(.caption).foregroundStyle(.secondary)
                        Picker("Link access", selection: $model.sharing) { ForEach(DriveSharing.allCases) { sharing in Text(sharing.title).tag(sharing) } }
                        Text(model.sharing == .anyoneWithLink ? "New uploads receive read-only access for anyone who has the link. They are not listed publicly." : "No new public permission is added. Existing or inherited folder permissions still apply.").font(.caption).foregroundStyle(.secondary)
                        if drive.busy { HStack { ProgressView().controlSize(.small); Button("Cancel sign-in") { drive.cancelConnection() } } }
                        else if drive.isConnected {
                            HStack {
                                Button("Switch Google account…") { Task { await drive.connect() } }.disabled(drive.busy)
                                Button("Disconnect") { drive.disconnect() }.disabled(drive.busy)
                            }
                        }
                        else {
                            Button("Sign in with Google") { Task { await drive.connect() } }.buttonStyle(.borderedProminent)
                        }
                        Text(drive.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if model.pendingUploadCount > 0 { Text("Retry sends pending images to the current account and folder. Already uploaded files only retry their existing link. The original link-access choice is kept.").font(.caption).foregroundStyle(.secondary); HStack { Text("\(model.pendingUploadCount) pending uploads").font(.caption); Spacer(); Button("Retry pending") { model.retryPendingUploads(drive) }.disabled(!drive.isConnected || model.busy); Button("Show files") { model.showPendingUploads() } } }
                    }.disabled(model.busy)
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Capture appearance").font(.headline)
                        Toggle("Balance content automatically on capture", isOn: $model.autoBalanceCapture)
                        Toggle("Match background color on capture", isOn: $model.autoMatchBackground)
                        Toggle("Apply window framing on window captures", isOn: $model.autoWindowStyle)
                        Picker("Capture timer", selection: $capture.delaySeconds) { ForEach(CaptureService.supportedDelays, id: \.self) { n in Text(n == 0 ? "No delay" : "\(n) seconds").tag(n) } }
                        Text("Native device pixels are kept. On a Retina display, these are typically 2× the logical screen dimensions. PNG export preserves this detail.").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Capture shortcuts & permissions", isExpanded: $advanced) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(CaptureMode.allCases) { mode in HStack { Text(mode.title).frame(width: 150, alignment: .leading); ShortcutRecorder(mode: mode).environmentObject(capture) } }
                            Text(capture.status).font(.caption).foregroundStyle(.secondary)
                            HStack { Button("Reset shortcuts") { capture.resetShortcuts() }; Button("Screen Recording settings") { capture.openScreenRecordingSettings() } }
                        }.padding(.top, 12)
                    }
                }.padding(.trailing, 6)
            }
        }.padding(28).frame(width: 650, height: 690).preferredColorScheme(.dark)
    }
}

struct ShortcutRecorder: View {
    @EnvironmentObject var capture: CaptureService
    var mode: CaptureMode
    @ViewState private var recording = false
    @ViewState private var monitor: Any?
    var body: some View {
        Button(recording ? "Press shortcut… (Esc cancels)" : capture.shortcutDisplay(for: mode)) {
            if recording { stop(); return }; recording = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { stop(); return nil }
                var mods: UInt32 = 0
                if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
                if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
                if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
                if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
                _ = capture.updateShortcut(for: mode, keyCode: UInt32(event.keyCode), modifiers: mods); stop(); return nil
            }
        }.font(.system(size: 12, design: .monospaced)).frame(maxWidth: .infinity).onDisappear { stop() }
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = false }
}
