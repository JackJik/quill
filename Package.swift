// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Quill",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "Quill",
            path: "Sources/Quill"
        )
    ]
)
