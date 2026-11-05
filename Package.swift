// swift-tools-version:5.9
import PackageDescription
import Foundation

/// The package folder, so linker flags can point at files in it from any working directory.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

// All app code lives in TUMKit (a library), so Xcode previews work on every screen.
// The TUM executable is only a thin launcher that calls TUMMain.main().
let package = Package(
    name: "TUM",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TUM", targets: ["TUM"])
    ],
    targets: [
        .target(
            name: "TUMKit",
            path: "Sources/TUM",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "TUM",
            dependencies: ["TUMKit"],
            path: "Sources/TUMLauncher",
            // Record macOS SDK 26 in the app, so it gets Liquid Glass when run from Xcode (⌘R) too.
            // Without this SwiftPM records SDK 13.0 and macOS shows the old look.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "13.0", "-Xlinker", "26.0"]),
                // Debug builds only: embed a small Info.plist in the bare executable that Xcode ⌘R
                // runs, so macOS sees a bundle identifier (edu.umd.inst474.tum.dev, shared with dev.sh's "TUM Dev"). Without it
                // the console fills with "linkd.autoShortcut" and "missing main bundle identifier"
                // messages. Release builds get their Info.plist from the .app (make_dmg.sh).
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", "\(root)/Support/DebugInfo.plist"], .when(configuration: .debug))
            ]
        )
    ]
)
