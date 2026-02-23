import AppKit

@main
enum WhispererAppMain {
    static func main() {
        let app = NSApplication.shared

        // Start diagnostic log file — critical for debugging Finder launches
        // where stdout/stderr go nowhere.
        DiagnosticLog.startSession()
        DiagnosticLog.log("main() entered")

        // Check if Info.plist LSUIElement is set
        if let lsui = Bundle.main.object(forInfoDictionaryKey: "LSUIElement") {
            DiagnosticLog.log("Info.plist LSUIElement: \(lsui)")
        } else {
            DiagnosticLog.log("Info.plist LSUIElement: NOT SET (starts as .regular)")
        }

        DiagnosticLog.log("Activation policy before run: \(app.activationPolicy().rawValue)")

        // DO NOT set activation policy here — let the app start as .regular
        // (visible in Dock) first. This guarantees WindowServer registration.
        // We'll switch to .accessory (no Dock icon) AFTER confirming the
        // status item is visible and hotkeys are working.

        let delegate = AppDelegate()
        app.delegate = delegate

        DiagnosticLog.log("Entering run loop...")
        app.run()
    }
}
