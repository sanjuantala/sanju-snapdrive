import AppKit
let out = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let bg = NSBezierPath(roundedRect: NSRect(x: 45,y: 45,width: 934,height: 934),xRadius: 210,yRadius: 210)
let gradient = NSGradient(starting: NSColor(srgbRed: 0.62,green: 0.52,blue: 1,alpha: 1), ending: NSColor(srgbRed: 0.27,green: 0.24,blue: 0.68,alpha: 1))!
gradient.draw(in: bg,angle: -60)
NSColor.white.withAlphaComponent(0.96).setStroke()
let camera = NSBezierPath(roundedRect: NSRect(x: 214,y: 310,width: 590,height: 410),xRadius: 75,yRadius: 75); camera.lineWidth = 35; camera.stroke()
let lens = NSBezierPath(ovalIn: NSRect(x: 385,y: 405,width: 215,height: 215)); lens.lineWidth = 32; lens.stroke()
let top = NSBezierPath(roundedRect: NSRect(x: 350,y: 708,width: 170,height: 58),xRadius: 24,yRadius: 24); NSColor.white.setFill();top.fill()
NSColor(srgbRed: 0.67,green: 1,blue: 0.8,alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 662,y: 628,width: 45,height: 45)).fill()
let badge = NSBezierPath(ovalIn: NSRect(x: 657,y: 210,width: 205,height: 205)); NSColor(srgbRed: 0.15,green: 0.18,blue: 0.33,alpha: 1).setFill();badge.fill()
let arrow = NSBezierPath();arrow.move(to: NSPoint(x: 759,y: 255));arrow.line(to: NSPoint(x: 759,y: 365));arrow.move(to: NSPoint(x: 711,y: 318));arrow.line(to: NSPoint(x: 759,y: 365));arrow.line(to: NSPoint(x: 807,y: 318));arrow.lineWidth = 23;arrow.lineCapStyle = .round;arrow.lineJoinStyle = .round;NSColor.white.setStroke();arrow.stroke()
image.unlockFocus()
let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png,properties: [:])!
try data.write(to: URL(fileURLWithPath: out))
