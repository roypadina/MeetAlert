// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "MeetAlert",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "MeetAlert", path: "Sources/MeetAlert")]
)
