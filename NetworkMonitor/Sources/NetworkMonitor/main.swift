import AppKit

/// App entry point using @main for Swift 6 concurrency safety.
@main
struct AppEntry {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
