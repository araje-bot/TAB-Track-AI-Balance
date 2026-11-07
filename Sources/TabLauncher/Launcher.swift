import TabKit

/// Starts TAB. Everything else lives in TabKit (Sources/Tab), so Xcode previews work there.
@main
enum Launcher {
    @MainActor static func main() { TabMain.main() }
}
