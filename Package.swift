// swift-tools-version: 5.9
import PackageDescription

// SchoolCore: what every provider shares (JSON, HTTP transport, Keychain).
// LMSKit: the learning platform (assessments, timetable, reports, news); SEQTA is its provider.
// CanteenKit: lunch orders and student balances; My Student Account is its provider.
// LMSKit and CanteenKit don't depend on each other, so either can gain providers independently.
let package = Package(
    name: "SEQTADisengage",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "LMSKit", targets: ["LMSKit"]),
        .library(name: "CanteenKit", targets: ["CanteenKit"])
    ],
    targets: [
        .target(name: "SchoolCore"),
        .target(name: "LMSKit", dependencies: ["SchoolCore"]),
        .target(name: "CanteenKit", dependencies: ["SchoolCore"]),
        .testTarget(name: "LMSKitTests", dependencies: ["LMSKit"]),
        .testTarget(name: "CanteenKitTests", dependencies: ["CanteenKit"])
    ]
)
