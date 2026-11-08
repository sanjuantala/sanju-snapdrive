// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SnapDrive", platforms: [.macOS(.v13)], products: [.executable(name: "SnapDrive", targets: ["SnapDrive"])], targets: [.executableTarget(name: "SnapDrive")])
