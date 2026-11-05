import TUMKit

/// Starts TUM. Everything else lives in TUMKit (Sources/TUM), so Xcode previews work there.
@main
enum Launcher {
    @MainActor static func main() { TUMMain.main() }
}
