// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AutoClicker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AutoClicker",
            path: "Sources/AutoClicker",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
