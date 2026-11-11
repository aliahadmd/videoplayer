// swift-tools-version: 6.2
import PackageDescription
import Foundation

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "VideoPlayer",
    platforms: [.macOS("27.2")],
    products: [.executable(name: "VideoPlayer", targets: ["NativePlayer"])],
    targets: [
        .systemLibrary(name: "CMPV", path: "Sources/CMPV"),
        .target(name: "PlayerCore"),
        .executableTarget(
            name: "NativePlayer", dependencies: ["PlayerCore", "CMPV"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.unsafeFlags(["-L", projectRoot + "/Vendor/lib", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", "-Xlinker", "-rpath", "-Xlinker", projectRoot + "/Vendor/lib"])]
        ),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"])
    ]
)
