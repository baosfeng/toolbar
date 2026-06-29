import AppKit

// Entry point - runs on @MainActor
@MainActor
func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // Hide from Dock
    app.run()
}

main()
