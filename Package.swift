// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tessera",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tessera", targets: ["Tessera"]),
    ],
    targets: [
        // Instant space switching via synthetic Dock swipe gestures.
        // Vendored unmodified from InstantSpaceSwitcher (MIT) — see UPSTREAM.
        .target(
            name: "SpaceSwitchEngine",
            exclude: ["LICENSE-InstantSpaceSwitcher", "UPSTREAM"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        // Pure, AppKit-free model + geometry: commands, shortcuts, layout math.
        .target(name: "TesseraCore"),
        .executableTarget(
            name: "Tessera",
            dependencies: ["SpaceSwitchEngine", "TesseraCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "TesseraCoreTests", dependencies: ["TesseraCore"]),
    ]
)
