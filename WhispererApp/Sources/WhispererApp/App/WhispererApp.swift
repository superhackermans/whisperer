import AppKit

@main
enum WhispererAppMain {
    static func main() {
        let app = NSApplication.shared

        // DO NOT set activation policy here — let the app start as .regular
        // (visible in Dock) first. This guarantees WindowServer registration.
        // We'll switch to .accessory (no Dock icon) AFTER confirming the
        // status item is visible.

        let delegate = AppDelegate()
        app.delegate = delegate

        print("=== WHISPERER DIAGNOSTIC BOOT ===")
        print("PID: \(ProcessInfo.processInfo.processIdentifier)")
        print("Bundle: \(Bundle.main.bundlePath)")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // Check if Info.plist LSUIElement is being read
        if let lsui = Bundle.main.object(forInfoDictionaryKey: "LSUIElement") {
            print("Info.plist LSUIElement: \(lsui)")
        } else {
            print("Info.plist LSUIElement: NOT SET")
        }

        print("Activation policy before run: \(app.activationPolicy().rawValue)")
        print("Entering run loop...")
        app.run()
    }
}
