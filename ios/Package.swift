// swift-tools-version:5.9
// Lets SourPipe/Core build and test without Xcode, including on Linux: `swift test` in this folder.
// The app itself is built from SourPipe.xcodeproj.
import PackageDescription

let package = Package(
    name: "SourPipeCore",
    products: [.library(name: "SourPipeCore", targets: ["SourPipeCore"])],
    targets: [
        .target(name: "SourPipeCore", path: "SourPipe/Core"),
        .testTarget(name: "SourPipeCoreTests", dependencies: ["SourPipeCore"],
                    path: "Tests/SourPipeCoreTests",
                    resources: [.copy("Fixtures")]),
    ]
)
