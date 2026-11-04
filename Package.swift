// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "MeetAlert",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetAlert",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/MeetAlert",
            // Sparkle.framework is embedded in Contents/Frameworks (build.sh).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "MeetAlertTests", dependencies: ["MeetAlert"], path: "Tests/MeetAlertTests"),
    ]
)
