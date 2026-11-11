// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SEQTADisengage",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "SEQTAKit", targets: ["SEQTAKit"])],
    targets: [
        .target(name: "SEQTAKit"),
        .testTarget(name: "SEQTAKitTests", dependencies: ["SEQTAKit"])
    ]
)
