// swift-tools-version:5.9
import PackageDescription
import Foundation

/// The package folder, so linker flags can point at files in it from any working directory.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

// All app code lives in TabKit (a library), so Xcode previews work on every screen.
// The TAB executable is only a thin launcher that calls TabMain.main().
let package = Package(
    name: "TAB",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TAB", targets: ["TAB"])
    ],
    targets: [
        .target(
            name: "TabKit",
            path: "Sources/Tab",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "TAB",
            dependencies: ["TabKit"],
            path: "Sources/TabLauncher",
            // Record macOS SDK 26 in the app, so it gets Liquid Glass when run from Xcode (⌘R) too.
            // Without this SwiftPM records SDK 13.0 and macOS shows the old look.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "13.0", "-Xlinker", "26.0"]),
                // Debug builds only: embed a small Info.plist in the bare executable that Xcode ⌘R
                // runs, so macOS sees a bundle identifier (edu.umd.inst474.tab.dev, shared with dev.sh's "TAB Dev"). Without it
                // the console fills with "linkd.autoShortcut" and "missing main bundle identifier"
                // messages. Release builds get their Info.plist from the .app (make_dmg.sh).
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", "\(root)/Support/DebugInfo.plist"], .when(configuration: .debug))
            ]
        )
    ]
)
