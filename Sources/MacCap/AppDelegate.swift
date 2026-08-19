import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = AppController()
        appController = controller
        controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        appController?.stop()
    }
}
