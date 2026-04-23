// swift-tools-version: 6.3
import PackageDescription

let libPath = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "embercap",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "embercap"
        ),
        .testTarget(
            name: "embercapTests",
            dependencies: [
                "embercap",
                .product(name: "Testing", package: "swift-testing"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", libPath,
                    "-Xlinker", "-rpath", "-Xlinker", libPath,
                ])
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
