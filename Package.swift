// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QuotaBar", targets: ["QuotaBar"]),
    ],
    targets: [
        .target(
            name: "QuotaBarCore",
            path: "Sources/QuotaBarCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("SwiftUI")]
        ),
        .executableTarget(
            name: "QuotaBar",
            dependencies: ["QuotaBarCore"],
            path: "Sources/QuotaBar",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("SwiftUI")]
        ),
        .target(
            name: "QuotaBarWidget",
            dependencies: ["QuotaBarCore"],
            path: "Sources/QuotaBarWidget",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-bundle",
                    "-Xlinker", "-Wl,-rpath,@executable_path/../../../../Frameworks",
                    "-Xlinker", "-Wl,-rpath,@executable_path/../../../../../Frameworks",
                ]),
                .linkedFramework("WidgetKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
    ]
)