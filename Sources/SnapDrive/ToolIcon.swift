import AppKit
import SwiftUI

/// Lucide 1.68.0 SVG geometry, drawn as SwiftUI paths rather than template NSImages.
/// This keeps AppKit Menu labels from substituting black template ink in dark mode.
struct ToolIcon: View {
    let name: String
    var size: CGFloat = 19
    var menuGlyph = false
    var menuColor: Color = Color(white: 0.84)
    var body: some View {
        Group {
            if name == "hand" { Image(systemName: "hand.raised").font(.system(size: size * 0.9, weight: .medium)) }
            else if menuGlyph { LucideGlyph(name: name).stroke(menuColor, style: stroke) }
            else { LucideGlyph(name: name).stroke(style: stroke) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
    private var stroke: StrokeStyle { StrokeStyle(lineWidth: size / 12, lineCap: .round, lineJoin: .round) }
}

private struct LucideGlyph: Shape {
    let name: String
    func path(in rect: CGRect) -> Path {
        LucidePaths.path(name).applying(CGAffineTransform(a: rect.width / 24, b: 0, c: 0, d: rect.height / 24, tx: rect.minX, ty: rect.minY))
    }
}

struct ToolIconButtonStyle:ButtonStyle {
    var isSelected=false
    private let selectedTint=Color(red:0.64,green:0.59,blue:1)
    @Environment(\.isEnabled) private var enabled
    @ViewState private var hovering=false
    func makeBody(configuration:Configuration)->some View {
        configuration.label.frame(width:34,height:34)
            .foregroundStyle(isSelected ? selectedTint:Color.primary.opacity(0.78))
            .background(RoundedRectangle(cornerRadius:8).fill(isSelected ? selectedTint.opacity(0.19):Color.white.opacity(configuration.isPressed ? 0.12:hovering ? 0.06:0)))
            .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(isSelected ? selectedTint.opacity(0.32):Color.clear,lineWidth:1))
            .contentShape(RoundedRectangle(cornerRadius:8))
            .opacity(enabled ? 1:0.33)
            .onHover{hovering=$0}
    }
}

@MainActor enum ToolIconLibrary {
    private static var cache: [String: NSImage] = [:]
    static var names: [String] { LucidePaths.commands.keys.sorted() }
    static func image(_ name: String) -> NSImage {
        if let image = cache[name] { return image }
        let image = nativeImage(name)
        image.isTemplate = true; cache[name] = image
        return image
    }
    static func assetURL(_ name: String) -> URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Icons/\(name).svg")
        #if SNAPDRIVE_BUNDLED_ASSETS
        let candidates = [bundled]
        #else
        let candidates = [bundled, URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Icons/\(name).svg")]
        #endif
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func nativeImage(_ name: String) -> NSImage {
        let cgPath = LucidePaths.path(name).cgPath
        return NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState(); defer { context.restoreGState() }
            context.setStrokeColor(NSColor.black.cgColor); context.setLineWidth(2)
            context.setLineCap(.round); context.setLineJoin(.round)
            context.addPath(cgPath); context.strokePath()
            return true
        }
    }
}

/// Generated from the bundled, unmodified Lucide SVG files; see Icons/LICENSE.txt.
private enum LucidePaths {
    enum Command {
        case m(CGFloat, CGFloat), l(CGFloat, CGFloat)
        case c(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        case q(CGFloat, CGFloat, CGFloat, CGFloat)
        case r(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        case e(CGFloat, CGFloat, CGFloat, CGFloat)
        case z
    }
    static func path(_ name: String) -> Path {
        var path = Path()
        for command in commands[name] ?? commands["select"]! {
            switch command {
            case .m(let x, let y): path.move(to: CGPoint(x: x, y: y))
            case .l(let x, let y): path.addLine(to: CGPoint(x: x, y: y))
            case .c(let x1, let y1, let x2, let y2, let x, let y): path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case .q(let x1, let y1, let x, let y): path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x1, y: y1))
            case .r(let x, let y, let w, let h, let radius): path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: radius, height: radius))
            case .e(let x, let y, let w, let h): path.addEllipse(in: CGRect(x: x, y: y, width: w, height: h))
            case .z: path.closeSubpath()
            }
        }
        return path
    }
    static let commands: [String: [Command]] = [
        "arrow":[.m(7,7),.l(17,7),.l(17,17),.m(7,17),.l(17,7)],
        "blur":[.m(12,22),.c(15.865993,22,19,18.865993,19,15),.c(19,13,18,11.1,16,9.5),.c(14,7.9,12.5,5.5,12,3),.c(11.5,5.5,10,7.9,8,9.5),.c(6,11.1,5,13,5,15),.c(5,18.865993,8.134007,22,12,22),.z],
        "capture":[.m(3,7),.l(3,5),.c(3,3.895431,3.895431,3,5,3),.l(7,3),.m(17,3),.l(19,3),.c(20.104569,3,21,3.895431,21,5),.l(21,7),.m(21,17),.l(21,19),.c(21,20.104569,20.104569,21,19,21),.l(17,21),.m(7,21),.l(5,21),.c(3.895431,21,3,20.104569,3,19),.l(3,17)],
        "chevron":[.m(6,9),.l(12,15),.l(18,9)],
        "clear":[.m(21,21),.l(8,21),.c(7.467388,21.001217,6.95629,20.789939,6.58,20.413),.l(2.586,16.414),.c(1.805236,15.633,1.805236,14.367,2.586,13.586),.l(12.586,3.586),.c(12.961096,3.210752,13.469927,2.999927,14.0005,2.999927),.c(14.531073,2.999927,15.039904,3.210752,15.415,3.586),.l(21.414,9.586),.c(22.194764,10.367,22.194764,11.633,21.414,12.414),.l(12.834,21),.m(5.082,11.09),.l(13.91,19.918)],
        "copy":[.r(8,8,14,14,2),.m(4,16),.c(2.9,16,2,15.1,2,14),.l(2,4),.c(2,2.9,2.9,2,4,2),.l(14,2),.c(15.1,2,16,2.9,16,4)],
        "crop":[.m(6,2),.l(6,16),.c(6,17.104569,6.895431,18,8,18),.l(22,18),.m(18,22),.l(18,8),.c(18,6.895431,17.104569,6,16,6),.l(2,6)],
        "ellipse":[.e(2,2,20,20)],
        "export":[.m(12,3),.l(12,15),.m(17,8),.l(12,3),.l(7,8),.m(21,15),.l(21,19),.c(21,20.104569,20.104569,21,19,21),.l(5,21),.c(3.895431,21,3,20.104569,3,19),.l(3,15)],
        "history":[.m(3,12),.c(3,16.970563,7.029437,21,12,21),.c(16.970563,21,21,16.970563,21,12),.c(21,7.029437,16.970563,3,12,3),.c(9.483952,3.009465,7.068969,3.991224,5.26,5.74),.l(3,8),.m(3,3),.l(3,8),.l(8,8),.m(12,7),.l(12,12),.l(16,14)],
        "link":[.m(10,13),.c(10.868955,14.161693,12.199627,14.8887,13.64665,14.992333),.c(15.093672,15.095966,16.514366,14.566006,17.54,13.54),.l(20.54,10.54),.c(22.434861,8.578106,22.407762,5.459576,20.479093,3.530907),.c(18.550424,1.602238,15.431894,1.575139,13.47,3.47),.l(11.75,5.18),.m(14,11),.c(13.131045,9.838307,11.800373,9.1113,10.35335,9.007667),.c(8.906328,8.904034,7.485634,9.433994,6.46,10.46),.l(3.46,13.46),.c(1.565139,15.421894,1.592238,18.540424,3.520907,20.469093),.c(5.449576,22.397762,8.568106,22.424861,10.53,20.53),.l(12.24,18.82)],
        "magnifier":[.e(3,3,16,16),.m(21,21),.l(16.65,16.65),.m(11,8),.l(11,14),.m(8,11),.l(14,11)],
        "open":[.m(6,14),.l(7.5,11.1),.c(7.832288,10.440079,8.50134,10.017115,9.24,10),.l(20,10),.c(20.619191,9.998914,21.203969,10.284685,21.583574,10.773867),.c(21.963179,11.263049,22.094799,11.90047,21.94,12.5),.l(20.4,18.5),.c(20.17076,19.387928,19.367021,20.006188,18.45,20),.l(4,20),.c(2.895431,20,2,19.104569,2,18),.l(2,5),.c(2,3.895431,2.895431,3,4,3),.l(7.9,3),.c(8.579667,2.993336,9.216198,3.332317,9.59,3.9),.l(10.4,5.1),.c(10.769922,5.66172,11.397414,5.999889,12.07,6),.l(18,6),.c(19.104569,6,20,6.895431,20,8),.l(20,10)],
        "paste":[.r(8,2,8,4,1),.m(16,4),.l(18,4),.c(19.104569,4,20,4.895431,20,6),.l(20,20),.c(20,21.104569,19.104569,22,18,22),.l(6,22),.c(4.895431,22,4,21.104569,4,20),.l(4,6),.c(4,4.895431,4.895431,4,6,4),.l(8,4)],
        "pixelate":[.r(3,3,18,18,2),.m(3,9),.l(21,9),.m(3,15),.l(21,15),.m(9,3),.l(9,21),.m(15,3),.l(15,21)],
        "rectangle":[.r(2,6,20,12,2)],
        "redact":[.m(10.733,5.076),.c(15.520139,4.505508,20.101173,7.19362,21.938,11.651),.c(22.021341,11.875515,22.021341,12.122485,21.938,12.347),.c(21.570498,13.237995,21.08481,14.075505,20.494,14.837),.m(14.084,14.158),.c(12.906863,15.294917,11.035746,15.278657,9.878544,14.121456),.c(8.721343,12.964254,8.705083,11.093137,9.842,9.916),.m(17.479,17.499),.c(14.794909,19.088947,11.552508,19.434478,8.593631,18.445882),.c(5.634754,17.457287,3.251267,15.232081,2.062,12.348),.c(1.978659,12.123485,1.978659,11.876515,2.062,11.652),.c(2.948632,9.501855,4.508673,7.697247,6.508,6.509),.m(2,2),.l(22,22)],
        "redo":[.m(15,14),.l(20,9),.l(15,4),.m(20,9),.l(9.5,9),.c(6.462434,9,4,11.462434,4,14.5),.c(4,17.537566,6.462434,20,9.5,20),.l(13,20)],
        "select":[.m(4.037,4.688),.c(3.956239,4.501616,3.997543,4.28481,4.141177,4.141177),.c(4.28481,3.997543,4.501616,3.956239,4.688,4.037),.l(20.688,10.537),.c(20.88753,10.618291,21.012549,10.818256,20.998247,11.033235),.c(20.983945,11.248214,20.83354,11.429856,20.625,11.484),.l(14.501,13.064),.c(13.796329,13.245158,13.245629,13.794709,13.063,14.499),.l(11.484,20.625),.c(11.429856,20.83354,11.248214,20.983945,11.033235,20.998247),.c(10.818256,21.012549,10.618291,20.88753,10.537,20.688),.z],
        "text":[.m(12,4),.l(12,20),.m(4,7),.l(4,5),.c(4,4.447715,4.447715,4,5,4),.l(19,4),.c(19.552285,4,20,4.447715,20,5),.l(20,7),.m(9,20),.l(15,20)],
        "textselect":[.m(14,21),.l(15,21),.m(14,3),.l(15,3),.m(19,3),.c(20.104569,3,21,3.895431,21,5),.m(21,14),.l(21,15),.m(21,19),.c(21,20.104569,20.104569,21,19,21),.m(21,9),.l(21,10),.m(3,14),.l(3,15),.m(3,9),.l(3,10),.m(5,21),.c(3.895431,21,3,20.104569,3,19),.m(5,3),.c(3.895431,3,3,3.895431,3,5),.m(7,12),.l(17,12),.m(7,16),.l(13,16),.m(7,8),.l(15,8),.m(9,21),.l(10,21),.m(9,3),.l(10,3)],
        "trash":[.m(10,11),.l(10,17),.m(14,11),.l(14,17),.m(19,6),.l(19,20),.c(19,21.104569,18.104569,22,17,22),.l(7,22),.c(5.895431,22,5,21.104569,5,20),.l(5,6),.m(3,6),.l(21,6),.m(8,6),.l(8,4),.c(8,2.895431,8.895431,2,10,2),.l(14,2),.c(15.104569,2,16,2.895431,16,4),.l(16,6)],
        "undo":[.m(9,14),.l(4,9),.l(9,4),.m(4,9),.l(14.5,9),.c(17.537566,9,20,11.462434,20,14.5),.c(20,17.537566,17.537566,20,14.5,20),.l(11,20)]
    ]
}

/// A native popover menu whose trigger stays in SwiftUI. AppKit's Menu label
/// bridge does not render custom SVG Shape labels consistently in dark mode.
struct ToolMenuAction: Identifiable {
    let id = UUID()
    let title: String
    var enabled: Bool
    var destructive: Bool
    let action: () -> Void
    init(_ title: String, enabled: Bool = true, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.enabled = enabled; self.destructive = destructive; self.action = action
    }
}

struct ToolActionMenu<Label: View>: View {
    private let title: String
    private let actions: [ToolMenuAction]
    private let label: Label
    @ViewState private var expanded = false
    @Environment(\.isEnabled) private var enabled
    init(_ title: String, actions: [ToolMenuAction], @ViewBuilder label: () -> Label) {
        self.title = title; self.actions = actions; self.label = label()
    }
    var body: some View {
        Button { expanded.toggle() } label: { label.opacity(enabled ? 1 : 0.42) }
            .buttonStyle(.plain).accessibilityLabel(title).accessibilityHint("Open menu")
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(actions) { item in
                        Button { expanded = false; item.action() } label: {
                            Text(item.title).font(.system(size: 12, weight: .medium)).foregroundStyle(item.destructive ? Color.red : Color.primary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(minHeight: 31).contentShape(Rectangle())
                        }.buttonStyle(ToolMenuItemStyle()).disabled(!item.enabled)
                    }
                }.padding(6).frame(minWidth: 190).background(Color(white: 0.16)).preferredColorScheme(.dark)
                    .onExitCommand { expanded = false }
            }
    }
}

private struct ToolMenuItemStyle: ButtonStyle {
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Color.white.opacity(configuration.isPressed ? 0.13 : hovering && enabled ? 0.075 : 0), in: RoundedRectangle(cornerRadius: 5)).opacity(enabled ? 1 : 0.36).onHover { hovering = $0 }
    }
}

/// A compact editable numeric control, with presets as shortcuts rather than limits.
struct ToolNumericControl:View {
    var title:String
    var value:Double
    var range:ClosedRange<Double>
    var presets:[Double]
    var onCommit:(Double)->Void
    @ViewState private var dragStart:Double?
    @ViewState private var dragValue:Double?
    var body:some View {
        HStack(spacing:5){
            HStack(spacing:3) {
                Image(systemName:"arrow.left.and.right").font(.system(size:8,weight:.semibold)).foregroundStyle(.tertiary)
                Text(title).font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
            }.frame(height:30).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:2).onChanged{gesture in
                    if dragStart == nil{dragStart=value}
                    let step=NSEvent.modifierFlags.contains(.shift) ? 0.1:0.5
                    dragValue=min(range.upperBound,max(range.lowerBound,(dragStart ?? value)+Double(gesture.translation.width)*step))
                }.onEnded{_ in
                    if let number=dragValue{onCommit((number*10).rounded()/10)}
                    dragStart=nil;dragValue=nil
                })
                .help("Drag left or right to adjust \(title.lowercased()). Hold Shift for precision.")
                .accessibilityLabel(title + "; drag to adjust")
            ToolNumberField(value:dragValue ?? value,range:range,label:title + " in pixels",onCommit:onCommit).frame(width:44,height:26)
            Text("px").font(.system(size:10)).foregroundStyle(.tertiary)
            ToolActionMenu(title + " presets", actions: presets.map { number in
                ToolMenuAction("\(number.formatted(.number.precision(.fractionLength(0...1)))) px") { onCommit(number) }
            }) { ToolIcon(name:"chevron",size:11,menuGlyph:true).frame(width:23,height:28).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:5)) }
                .help("Choose a \(title.lowercased()) preset; type any value in the field")
        }.padding(.horizontal,7).frame(height:34).background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:7))
    }
}

struct ToolNumberField:NSViewRepresentable {
    var value:Double
    var range:ClosedRange<Double>
    var label:String="Custom value in pixels"
    var onCommit:(Double)->Void
    func makeCoordinator()->Coordinator{Coordinator(self)}
    func makeNSView(context:Context)->NSTextField {
        let field=NSTextField()
        field.delegate=context.coordinator;field.alignment = .right
        field.font=NSFont.monospacedDigitSystemFont(ofSize:12,weight:.medium)
        field.isBordered=false;field.drawsBackground=true;field.backgroundColor=NSColor.white.withAlphaComponent(0.055)
        field.focusRingType = .none;field.wantsLayer=true;field.layer?.cornerRadius=5
        field.stringValue=Coordinator.string(value);field.setAccessibilityLabel(label)
        return field
    }
    func updateNSView(_ field:NSTextField,context:Context){
        context.coordinator.parent=self
        if field.currentEditor()==nil{field.stringValue=Coordinator.string(value)}
    }
    final class Coordinator:NSObject,NSTextFieldDelegate {
        var parent:ToolNumberField
        init(_ parent:ToolNumberField){self.parent=parent}
        static func string(_ value:Double)->String{value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))}
        private func commit(_ field:NSTextField){
            let formatter=NumberFormatter();formatter.numberStyle = .decimal;formatter.locale = .current
            guard let parsed=formatter.number(from:field.stringValue.trimmingCharacters(in:.whitespaces))?.doubleValue,parsed.isFinite else{field.stringValue=Self.string(parent.value);return}
            let value=min(parent.range.upperBound,max(parent.range.lowerBound,parsed))
            field.stringValue=Self.string(value);parent.onCommit(value)
        }
        func controlTextDidEndEditing(_ notification:Notification){if let field=notification.object as? NSTextField{commit(field)}}
        func control(_ control:NSControl,textView:NSTextView,doCommandBy commandSelector:Selector)->Bool{
            guard let field=control as? NSTextField else{return false}
            if commandSelector==NSSelectorFromString("insertNewline:"){commit(field);field.window?.makeFirstResponder(nil);return true}
            if commandSelector==NSSelectorFromString("cancelOperation:"){field.stringValue=Self.string(parent.value);field.window?.makeFirstResponder(nil);return true}
            return false
        }
    }
}
