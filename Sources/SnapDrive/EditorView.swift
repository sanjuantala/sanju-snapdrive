import SwiftUI
import AppKit

struct EditorView: View {
    @EnvironmentObject var model: EditorModel
    @EnvironmentObject var capture: CaptureService
    @EnvironmentObject var drive: DriveService
    @ViewState private var presetName = ""
    @ViewState private var showPreset = false
    @ViewState private var dropping = false
    @ViewState private var backgroundTab = "Images"
    let accent = Color(red: 0.64, green: 0.59, blue: 1)
    var body: some View {
        VStack(spacing: 0) {
            primaryHeader
            toolStrip
            if capture.needsScreenPermission {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                    Text("If Screen Recording is already on, quit and reopen the app to apply it.").font(.system(size: 12))
                    Spacer()
                    Button("Screen Recording settings") { capture.openScreenRecordingSettings() }
                    Button("Quit app") { NSApp.terminate(nil) }
                }.padding(.horizontal, 16).padding(.vertical, 10).background(accent.opacity(0.12))
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if model.image == nil { welcome } else { EditorCanvas().environmentObject(model) }
                    statusBar
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.10))
                Divider()
                inspector.frame(width: 300).background(Color(white: 0.13))
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .background(Color(white: 0.12)).preferredColorScheme(.dark).tint(accent)
        .onDrop(of: [.fileURL, .image], isTargeted: $dropping) { providers in
            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { DispatchQueue.main.async { model.open(url) } } }; return true
            }
            if let provider = providers.first { _ = provider.loadObject(ofClass: NSImage.self) { image, _ in if let image = image as? NSImage { DispatchQueue.main.async { model.load(image) } } }; return true }; return false
        }
        .overlay { if dropping { RoundedRectangle(cornerRadius: 10).stroke(accent, lineWidth: 3).padding(3).allowsHitTesting(false) } }
        .overlay(alignment: .bottom) { FeedbackToast(message: model.toast).padding(.bottom, 48).animation(.easeOut(duration: 0.18), value: model.toast) }
        .sheet(isPresented: $model.showDrive) { DriveSettings().environmentObject(drive).environmentObject(model) }
        .sheet(isPresented: $model.showUploadResult) { UploadResultView().environmentObject(model).environmentObject(drive) }
        .sheet(isPresented: $model.showHistory) { historySheet }
        .sheet(isPresented: $model.showText) { textSheet }
        .sheet(isPresented: $model.showShortcuts) { shortcutsSheet }
        .alert("Sanju's SnapDrive", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .alert("Save appearance preset", isPresented: $showPreset) { TextField("Preset name", text: $presetName); Button("Save") { model.savePreset(presetName); presetName = "" }; Button("Cancel", role: .cancel) {} } message: { Text("Reuse this background, spacing, ratio, and watermark.") }
    }
    var primaryHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Button { capture.capture(.region) } label: {
                    HStack(spacing: 8) { ToolIcon(name: "capture", size: 18); Text("Capture region").font(.system(size: 12, weight: .semibold)) }.padding(.leading, 13).padding(.trailing, 11).frame(height: 34)
                }.buttonStyle(.plain).accessibilityIdentifier("capture.region").help("Capture a region · \(capture.shortcutDisplay(for: .region))")
                Rectangle().fill(.white.opacity(0.22)).frame(width: 1, height: 18)
                ToolActionMenu("More capture modes", actions: [
                    ToolMenuAction("Capture region") { capture.capture(.region) },
                    ToolMenuAction("Capture window") { capture.capture(.window) },
                    ToolMenuAction("Capture full screen") { capture.capture(.fullscreen) }
                ]) { ToolIcon(name: "chevron", size: 12, menuGlyph: true, menuColor: .white).frame(width: 30, height: 34) }
            }.foregroundStyle(.white).background(LinearGradient(colors: [accent, Color(red: 0.47, green: 0.40, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 9)).disabled(capture.busy)
            HStack(spacing: 2) {
                headerIcon("open", title: "Open image", hint: "Open image (⌘O)") { model.open() }
                headerIcon("paste", title: "Paste image", hint: "Paste image (⌘V)") { model.paste() }
            }
            Divider().frame(height: 22)
            headerIcon("history", title: "Screenshot history", hint: "Open screenshot history") { model.showHistory = true }
            Spacer(minLength: 8)
            if model.image != nil {
                Text(model.fileName).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 220)
            }
            Spacer(minLength: 8)
            headerIcon("copy", title: "Copy image", hint: "Copy the edited screenshot") { model.copyImage() }.disabled(model.image == nil || model.busy)
            ToolActionMenu("Export", actions: [
                ToolMenuAction("Export image…") { model.save() },
                ToolMenuAction("Save to Drive folder", enabled: !model.busy) { model.saveToDriveFolder(drive) },
                ToolMenuAction("Share edited image…") { SharePresenter.present(model.renderedOutput()) }
            ]) { HStack(spacing: 6) { ToolIcon(name: "export", size: 17, menuGlyph: true); Text("Export").font(.system(size: 12, weight: .medium)); ToolIcon(name: "chevron", size: 10, menuGlyph: true) }.padding(.horizontal, 10).frame(height: 34).foregroundStyle(Color(white: 0.84)) }
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8)).disabled(model.image == nil || model.busy)
            Button { model.uploadAndCopy(drive) } label: {
                HStack(spacing: 7) { ToolIcon(name: "link", size: 17); Text("Upload & copy link").font(.system(size: 12, weight: .semibold)) }.padding(.horizontal, 13).frame(height: 34)
            }.buttonStyle(.plain).foregroundStyle(.white).background(Color(red: 0.14, green: 0.45, blue: 0.92), in: RoundedRectangle(cornerRadius: 9)).disabled(model.image == nil || model.busy || drive.busy).opacity(model.image == nil || model.busy || drive.busy ? 0.4 : 1).accessibilityIdentifier("editor.upload").help("Upload the edited image · \(model.sharing.title)")
        }.padding(.horizontal, 16).frame(height: 56).background(Color(white: 0.145)).overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
    }
    func headerIcon(_ icon: String, title: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { ToolIcon(name: icon, size: 18) }.buttonStyle(ToolIconButtonStyle()).accessibilityLabel(title).help(hint)
    }
    var toolStrip: some View {
        HStack(spacing: 8) {
            HStack(spacing: 1) {
                ForEach(Array(EditorTool.allCases.enumerated()), id: \.element) { index, tool in
                    Button {
                        NotificationCenter.default.post(name: .snapDriveFocusCanvas, object: nil)
                        if tool != .select { model.selectAnnotation(nil) }; model.tool = tool
                    } label: { ToolIcon(name: tool.rawValue) }
                        .buttonStyle(ToolIconButtonStyle(isSelected: model.tool == tool))
                        .accessibilityLabel(tool.title).accessibilityIdentifier("tool." + tool.rawValue)
                        .help("\(tool.title) · \(tool.shortcutLetter)" + (index < 9 ? " · \(index + 1)" : index == 9 ? " · 0" : ""))
                        .disabled(model.image == nil)
                }
            }
            Divider().frame(height: 22)
            HStack(spacing: 12) {
                ColorPicker("Annotation color", selection: Binding(get: { model.ink }, set: { model.setSelectedColor($0) }), supportsOpacity: false).labelsHidden().frame(width: 44, height: 28)
                ToolNumericControl(title: "Stroke", value: model.lineWidth, range: 0.5...1000, presets: [1, 2, 4, 6, 10, 16], onCommit: model.setSelectedLineWidth)
                    .help("Custom stroke width, 0.5–1,000 native pixels")
                if model.tool == .text || model.annotations.first(where: { $0.id == model.selectedID })?.kind == .text {
                    ToolNumericControl(title: "Font", value: model.fontSize, range: 8...512, presets: [16, 24, 28, 36, 48, 72], onCommit: model.setSelectedFontSize)
                        .help("Custom font size, 8–512 native pixels")
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                HStack(spacing: 0) {
                    Button { model.clearCanvas() } label: { HStack(spacing: 4) { ToolIcon(name: "clear", size: 16); Text("Clear").font(.system(size: 11, weight: .medium)) }.padding(.horizontal, 5).frame(height: 34) }
                        .buttonStyle(.plain).accessibilityLabel("Clear screenshot").accessibilityIdentifier("editor.clearCanvas").help("Clear the screenshot from this canvas · Undo restores it")
                    ToolActionMenu("Clear options", actions: [
                        ToolMenuAction("Clear screenshot") { model.clearCanvas() },
                        ToolMenuAction("Clear annotations only") { model.clearAnnotations() }
                    ]) { ToolIcon(name: "chevron", size: 10, menuGlyph: true).frame(width: 20, height: 34) }
                }.foregroundStyle(Color(white: 0.83)).disabled(model.image == nil).opacity(model.image == nil ? 0.35 : 1)
                Button { model.removeSelected() } label: { ToolIcon(name: "trash") }.buttonStyle(ToolIconButtonStyle()).accessibilityLabel("Delete annotation").accessibilityIdentifier("editor.delete").disabled(model.selectedID == nil).help("Delete selected annotation")
                Button { model.undo() } label: { ToolIcon(name: "undo") }.buttonStyle(ToolIconButtonStyle()).accessibilityLabel("Undo").accessibilityIdentifier("editor.undo").disabled(model.undoStack.isEmpty).help("Undo (⌘Z)")
                Button { model.redo() } label: { ToolIcon(name: "redo") }.buttonStyle(ToolIconButtonStyle()).accessibilityLabel("Redo").accessibilityIdentifier("editor.redo").disabled(model.redoStack.isEmpty).help("Redo (⇧⌘Z)")
            }
        }.padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 50).background(Color(white: 0.14))
    }
    var welcome: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(LinearGradient(colors: [accent.opacity(0.3), .pink.opacity(0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 116, height: 104).rotationEffect(.degrees(-7))
                Image(systemName: "camera.viewfinder").font(.system(size: 48, weight: .light)).foregroundStyle(accent)
            }.padding(.bottom, 8)
            VStack(spacing: 10) { Text("A better frame for every screenshot.").font(.system(size: 25, weight: .semibold)); Text("Capture. Polish. Save straight to Google Drive.").font(.system(size: 14)).foregroundStyle(.secondary) }
            HStack(spacing: 12) {
                Button { capture.capture(.region) } label: { Label("Capture a region", systemImage: "plus.viewfinder").padding(.horizontal, 8).padding(.vertical, 5) }.buttonStyle(.borderedProminent)
                Button { model.open() } label: { Label("Open image", systemImage: "folder").padding(.horizontal, 8).padding(.vertical, 5) }.buttonStyle(.bordered)
            }
            Text("Drop an image here, or paste with ⌘V").font(.caption).foregroundStyle(.tertiary)
            Button { model.showDrive = true } label: { Label(drive.syncFolder.isEmpty ? "Set up your Google Drive folder" : "Google Drive folder connected", systemImage: "externaldrive") }.buttonStyle(.link).padding(.top, 20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }
    var statusBar: some View {
        HStack(spacing: 8) {
            if capture.remainingSeconds > 0 { Button("Cancel \(capture.remainingSeconds)s") { capture.cancelCapture() }.font(.caption) }
            if model.busy || capture.busy || model.recognizing || model.previewRendering { ProgressView().controlSize(.small) }
            else { Circle().fill(accent).frame(width: 5, height: 5) }
            Text(capture.busy ? capture.status : model.status).lineLimit(1).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            if model.preview != nil {
                ToolActionMenu("Zoom", actions: [ToolMenuAction("Fit to window") { model.requestZoom("fit") }]
                    + [0.25,0.5,0.75,1,1.5,2,3,4].map { value in ToolMenuAction("\(Int(value*100))%") { model.requestZoom(value: value) } }) {
                        HStack(spacing: 4) { Text(model.zoom == 0 ? "Fit" : "\(Int((model.zoom*100).rounded()))%").monospacedDigit(); ToolIcon(name: "chevron", size: 9, menuGlyph: true) }.font(.system(size: 10)).padding(.horizontal, 7).frame(height: 24)
                    }.help("Pinch or ⌘/Ctrl + scroll to zoom · ⌘/Ctrl +/− · ⌘0 to fit")
                if model.uploadResult != nil { Button { model.showUploadResult = true } label: { Image(systemName: "link") }.buttonStyle(.plain).help("View uploaded screenshot link") }
            }
            if model.preview != nil { Text("Drag image out").font(.system(size: 10)).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.05), in: Capsule()).onDrag { model.dragProvider() } }
            if let image = model.image { let size = ImageEngine.dimensions(image: image, style: model.style); Text("\(Int(size.width)) × \(Int(size.height)) px").monospacedDigit().font(.system(size: 10)).foregroundStyle(.tertiary) }
            if let url = model.lastSavedURL { Button { if url.isFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { NSWorkspace.shared.open(url) } } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain).help("Show saved screenshot") }
        }.padding(.horizontal, 18).frame(height: 34).background(Color(white: 0.115))
    }
    var inspector: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(accent)
                    Text("Make it yours").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    ToolActionMenu("Appearance presets", actions: appearanceActions) {
                        Image(systemName: "square.stack").foregroundStyle(accent).frame(width: 26, height: 28)
                    }.help("Choose an appearance preset")
                    Button { showPreset = true } label: { Image(systemName: "plus").frame(width: 24, height: 26) }.buttonStyle(.plain).foregroundStyle(accent).help("Save current appearance as a preset").accessibilityLabel("Save appearance preset")
                }.padding(.horizontal, 16).frame(height: 47).background(.white.opacity(0.025))
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.tool == .magnifier || model.selectedMagnifier != nil { inspectorCard { magnifierControls }.id("magnifier.controls") }
                        inspectorCard {
                            sectionHeader("Background", icon: "photo.on.rectangle.angled")
                            backgroundControls
                        }
                        inspectorCard {
                            sectionHeader("Frame & spacing", icon: "rectangle.inset.filled")
                            VStack(spacing: 13) {
                                styleSlider("Padding", value: $model.style.padding, range: 0...220)
                                styleSlider("Inset", value: $model.style.inset, range: 0...80)
                                styleSlider("Corners", value: $model.style.radius, range: 0...100)
                                styleSlider("Shadow", value: $model.style.shadow, range: 0...100)
                            }
                            HStack(spacing: 8) {
                                Button { model.balance() } label: { Label("Balance content", systemImage: "rectangle.center.inset.filled").frame(maxWidth: .infinity) }.disabled(model.image == nil)
                                Button { model.autoColor() } label: { Image(systemName: "eyedropper.halffull").frame(width: 24) }.help("Match background to image").accessibilityLabel("Match background color").disabled(model.image == nil)
                            }.padding(.top, 2)
                        }
                        inspectorCard {
                            sectionHeader("Canvas", icon: "aspectratio")
                            Picker("Ratio", selection: $model.style.ratio) { Text("Auto · Original").tag(0.0); Text("1:1 · Square").tag(1.0); Text("4:3 · Classic").tag(4.0/3); Text("16:9 · Presentation").tag(16.0/9); Text("3:2 · Landscape").tag(1.5); Text("4:5 · Portrait").tag(0.8); Text("9:16 · Story").tag(9.0/16) }.onChange(of: model.style.ratio) { _ in model.refresh() }
                            TextField("Watermark (optional)", text: $model.style.watermark).textFieldStyle(.roundedBorder).accessibilityLabel("Watermark")
                        }
                        inspectorCard {
                            sectionHeader("Text & privacy", icon: "text.viewfinder")
                            Button { model.recognize() } label: { Label("Select & copy text", systemImage: "text.viewfinder").frame(maxWidth: .infinity, alignment: .leading) }
                            Button { model.recognize(redact: true) } label: { Label("Redact sensitive data", systemImage: "eye.slash").frame(maxWidth: .infinity, alignment: .leading) }
                            Text("Detects emails, IP addresses, cards, and key patterns. Review suggestions before sharing.").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.disabled(model.image == nil || model.recognizing)
                        inspectorCard {
                            sectionHeader("Export", icon: "square.and.arrow.up")
                            TextField("Screenshot filename", text: $model.fileName).textFieldStyle(.roundedBorder).accessibilityLabel("Screenshot filename")
                            Picker("Format", selection: $model.exportFormat) { Text("PNG").tag("png"); Text("JPEG").tag("jpeg") }.pickerStyle(.segmented)
                            if model.exportFormat != "png" { HStack { Text("Quality"); Slider(value: $model.quality, in: 0.1...1); Text("\(Int(model.quality * 100))%").monospacedDigit() }.font(.caption) }
                            Picker("Resolution", selection: $model.style.exportScale) { Text("Native · Original pixels").tag(1.0); Text("Half size · Downsample").tag(0.5); Text("2× larger · Upscale").tag(2.0) }
                            if let image = model.image {
                                let m = ImageEngine.sourceMetrics(image: image)
                                Label("\(Int(m.pixelSize.width)) × \(Int(m.pixelSize.height)) source · \(String(format: "%.1f", m.nativeScale))×", systemImage: "viewfinder").font(.system(size: 10)).foregroundStyle(accent)
                            }
                            Text(model.exportFormat == "png" && model.style.exportScale == 1 ? "Lossless PNG preserves native Retina detail in files and Drive uploads." : "PNG is lossless. Enlarging adds pixels, not captured detail. JPEG uses compression.").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        inspectorCard {
                            HStack { sectionHeader("Google Drive", icon: "externaldrive"); Spacer(); Button { model.showDrive = true } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Google Drive settings").accessibilityLabel("Google Drive settings") }
                            Label(drive.syncFolder.isEmpty ? "Choose a save folder" : URL(fileURLWithPath: drive.syncFolder).lastPathComponent, systemImage: drive.syncFolder.isEmpty ? "folder.badge.questionmark" : "checkmark.circle.fill").font(.caption).foregroundStyle(drive.syncFolder.isEmpty ? Color.secondary : Color.green).lineLimit(1).truncationMode(.middle)
                            Toggle("Automatic uploads", isOn: $drive.autoUpload).font(.caption).toggleStyle(.switch).controlSize(.small)
                            Text(drive.autoUpload ? "New images are sent to Drive immediately." : "Local first · Upload when you’re ready.").font(.system(size: 10)).foregroundStyle(.secondary)
                            Label(model.sharing.title, systemImage: "link").font(.system(size: 10)).foregroundStyle(.secondary)
                            Button { model.uploadAndCopy(drive) } label: { Label("Upload & copy link", systemImage: "link").frame(maxWidth: .infinity) }.disabled(model.image == nil || model.busy || drive.busy)
                            Button("Drive settings…") { model.showDrive = true }.frame(maxWidth: .infinity)
                        }
                    }.padding(12)
                }.controlSize(.small)
                .onChange(of: model.tool) { tool in if tool == .magnifier { DispatchQueue.main.async { proxy.scrollTo("magnifier.controls", anchor: .top) } } }
                .onChange(of: model.selectedID) { _ in if model.selectedMagnifier != nil { DispatchQueue.main.async { proxy.scrollTo("magnifier.controls", anchor: .top) } } }
            }
        }
    }
    func inspectorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.055), lineWidth: 1))
    }
    var appearanceActions: [ToolMenuAction] {
        [ToolMenuAction("Default style") { model.checkpoint(); model.style = EditorStyle() }]
        + model.presets.map { preset in ToolMenuAction(preset.name) { model.applyPreset(preset) } }
        + model.presets.map { preset in ToolMenuAction("Delete “\(preset.name)”", destructive: true) { model.deletePreset(preset.id) } }
    }
    var shortcutsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Keyboard shortcuts").font(.title2.bold()); Spacer(); Button("Done") { model.showShortcuts = false }.keyboardShortcut(.cancelAction) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 10) {
                        shortcutRow("Zoom in / out", "⌘ or Ctrl + / −")
                        shortcutRow("Fit to window", "⌘ or Ctrl 0")
                        shortcutRow("Actual pixels", "⌘ or Ctrl 1")
                        shortcutRow("Mouse zoom", "Pinch · ⌘/Ctrl-scroll")
                        shortcutRow("Undo / redo", "⌘Z / ⇧⌘Z")
                        shortcutRow("Open / export", "⌘O / ⌘S")
                        shortcutRow("Copy edited image", "⇧⌘C")
                        shortcutRow("Upload & copy link", "⇧⌘U")
                    }
                    Divider()
                    Text("Drawing tools").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        ForEach(EditorTool.allCases, id: \.self) { tool in
                            HStack(spacing: 8) { ToolIcon(name: tool.rawValue, size: 16).foregroundStyle(accent); Text(tool.title).font(.system(size: 12)); Spacer(); Text(tool.shortcutLetter).font(.system(size: 12, weight: .semibold, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 3).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 4)) }.padding(.trailing, 12)
                        }
                    }
                    Text("Use tool letters with the canvas focused. Text fields keep normal typing. Shift keeps arrows straight; Delete removes the selected annotation.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    VStack(spacing: 10) {
                        shortcutRow("Capture region", capture.shortcutDisplay(for: .region))
                        shortcutRow("Capture window", capture.shortcutDisplay(for: .window))
                        shortcutRow("Capture screen", capture.shortcutDisplay(for: .fullscreen))
                    }
                }
            }
        }.padding(24).frame(width: 500, height: 580).preferredColorScheme(.dark)
    }
    func shortcutRow(_ title: String, _ keys: String) -> some View {
        HStack { Text(title).font(.system(size: 12)); Spacer(); Text(keys).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary) }
    }
    var magnifierControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) { ToolIcon(name:"magnifier",size:16);Text("Magnifier").font(.system(size:12,weight:.semibold)) }.foregroundStyle(accent)
            HStack(spacing: 6) {
                Text("Zoom").font(.system(size:12));Spacer()
                ToolNumberField(value:model.magnification,range:1...8,label:"Magnifier zoom",onCommit:model.setSelectedMagnification).frame(width:44,height:24)
                Text("×").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing:6) {
                ForEach([1.5,2,3,4],id:\.self) { value in
                    Button("\(value.formatted(.number.precision(.fractionLength(0...1))))×") { model.setSelectedMagnification(value) }
                        .frame(maxWidth:.infinity).tint(model.magnification == value ? accent:.secondary)
                }
            }.font(.caption)
            if model.selectedMagnifier != nil, let image=model.image {
                HStack(spacing:6) {
                    Text("Diameter").font(.system(size:12));Spacer()
                    ToolNumberField(value:model.magnifierDiameter,range:8...max(8,min(ImageEngine.pixelSize(image).width,ImageEngine.pixelSize(image).height)),label:"Magnifier diameter in pixels",onCommit:model.setSelectedMagnifierDiameter).frame(width:54,height:24)
                    Text("px").font(.caption).foregroundStyle(.secondary)
                }
                Text("Drag the lens to move it. Use its corner handles to resize; Stroke and color control the border.").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            } else {
                Text("Click the image to place a lens, or drag to choose its size.").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    func sectionHeader(_ title: String, icon: String) -> some View { Label { Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.92)) } icon: { Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(accent) } }
    func styleSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let upperLimit: Double = ["Padding": 4096, "Inset": 2048, "Corners": 4096, "Shadow": 1024, "Background blur": 100][title] ?? range.upperBound
        let sliderValue = Binding(get: { min(range.upperBound, max(range.lowerBound, value.wrappedValue)) }, set: { value.wrappedValue = $0 })
        return VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 12)); Spacer()
                ToolNumberField(value: value.wrappedValue, range: 0...upperLimit, label: title + " in pixels", onCommit: { number in
                    guard value.wrappedValue != number else { return }; model.checkpoint(); value.wrappedValue = number
                }).frame(width: 44, height: 24)
                Text("px").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Slider(value: sliderValue, in: range, onEditingChanged: { editing in if editing { model.checkpoint() } })
        }
    }
    var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Background type", selection: $backgroundTab) { Text("Images").tag("Images"); Text("Gradients").tag("Gradients"); Text("Color").tag("Color") }.pickerStyle(.segmented).labelsHidden()
            if backgroundTab == "Images" {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 10) {
                    ForEach(BackgroundLibrary.assets) { asset in
                        Button { model.checkpoint(); model.style.background = "image:" + asset.id } label: {
                            VStack(spacing: 4) {
                                if let thumb = BackgroundLibrary.thumbnail(asset.id) { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill).frame(height: 44).clipped().clipShape(RoundedRectangle(cornerRadius: 6)).overlay { RoundedRectangle(cornerRadius: 6).stroke(model.style.background == "image:" + asset.id ? accent : .white.opacity(0.08), lineWidth: model.style.background == "image:" + asset.id ? 2 : 1) } }
                                Text(asset.name).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.buttonStyle(.plain).help(asset.name + (asset.photograph ? " · Original photo-style artwork" : " · Native 3840 × 2400 artwork"))
                    }
                }
                HStack { Button("Custom image…") { model.chooseBackground() }; Button("Wallpaper") { model.useWallpaper() } }.font(.caption)
            } else if backgroundTab == "Gradients" {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(["aurora", "dusk", "ocean", "rose", "mint", "sunset"], id: \.self) { name in
                        Button { model.checkpoint(); model.style.background = name } label: { RoundedRectangle(cornerRadius: 7).fill(swatch(name)).frame(height: 36).overlay { RoundedRectangle(cornerRadius: 7).stroke(model.style.background == name ? accent : .white.opacity(0.08), lineWidth: model.style.background == name ? 2 : 1) } }.buttonStyle(.plain).help(name.capitalized)
                    }
                }
            } else {
                ColorPicker("Background color", selection: Binding(get: { Color(nsColor: NSColor(hex: model.style.solidHex)) }, set: { model.style.solidHex = $0.hexString; model.style.background = "solid" }), supportsOpacity: false).font(.caption)
                Toggle("Transparent background", isOn: Binding(get: { model.style.background == "transparent" }, set: { model.checkpoint(); model.style.background = $0 ? "transparent" : "solid" })).font(.caption)
            }
            if model.style.background == "custom" || model.style.background.hasPrefix("image:") {
                styleSlider("Background blur", value: $model.style.backgroundBlur, range: 0...60)
                VStack(spacing: 4) { HStack { Text("Brightness"); Spacer(); Text("\(Int(model.style.backgroundBrightness * 100))%").monospacedDigit() }.font(.caption); Slider(value: $model.style.backgroundBrightness, in: 0.25...1.5, onEditingChanged: { if $0 { model.checkpoint() } }) }
            }
        }
    }
    func swatch(_ name: String) -> LinearGradient {
        let colors: [Color]
        switch name { case "aurora": colors = [.indigo, .purple, .pink]; case "dusk": colors = [.purple, .orange]; case "ocean": colors = [.blue, .cyan]; case "rose": colors = [.pink, Color(red: 1, green: 0.7, blue: 0.6)]; case "mint": colors = [.teal, .mint]; case "sunset": colors = [.orange, .red]; case "solid": colors = [Color(nsColor: NSColor(hex: model.style.solidHex))]; default: colors = [Color(white: 0.2), Color(white: 0.3)] }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var historySheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Screenshot history").font(.title2.bold()); Spacer(); Button("Done") { model.showHistory = false }.keyboardShortcut(.cancelAction) }
            Text("The latest 100 images and their edits, stored on this Mac.").foregroundStyle(.secondary).font(.caption)
            ScrollView { LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) { ForEach(model.history) { item in Button { model.restore(item) } label: { VStack(alignment: .leading, spacing: 6) { if let thumbnail = model.thumbnail(item) { Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit).frame(width: 170, height: 115).background(Color(white: 0.2)).clipShape(RoundedRectangle(cornerRadius: 6)) }; Text(item.name).font(.caption).lineLimit(1); Text(item.date, style: .date).font(.system(size: 10)).foregroundStyle(.secondary); if item.upload != nil { Label("Drive link saved", systemImage: "link").font(.system(size: 9)).foregroundStyle(accent) } }.frame(width: 170) }.buttonStyle(.plain) } } }
            if model.history.isEmpty { Text("Your captures and imported images will appear here.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            Button("Clear local history", role: .destructive) { model.clearHistory() }.disabled(model.history.isEmpty)
        }.padding(26).frame(width: 640, height: 490).preferredColorScheme(.dark)
    }
    var textSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Recognized text").font(.title2.bold()); Spacer(); Button("Done") { model.showText = false }.keyboardShortcut(.cancelAction) }
            Text("Select text to copy it, or copy a single line.").font(.caption).foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(Array(model.recognized.enumerated()), id: \.offset) { _, line in HStack(alignment: .top) { Text(line.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading); Button { model.copyText(line.text) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless) }; Divider() } }.padding(4) }
            if model.recognized.isEmpty { Text("No readable text found.").foregroundStyle(.secondary) }
            Button("Copy all text") { model.copyText(model.recognized.map(\.text).joined(separator: "\n")) }.disabled(model.recognized.isEmpty)
        }.padding(26).frame(width: 570, height: 470).preferredColorScheme(.dark)
    }
}
