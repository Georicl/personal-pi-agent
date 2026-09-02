import AppKit
import SwiftUI

@main
struct PersonalPiApp: App {
    @NSApplicationDelegateAdaptor(PersonalPiAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Personal Pi", id: "main") {
            PersonalPiRootContainer(appState: appDelegate.appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
    }
}

private struct PersonalPiRootContainer: View {
    @ObservedObject var appState: AppState
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    private var interfaceLocale: Locale {
        (AppLanguage(rawValue: languageRawValue) ?? .system).locale
    }

    var body: some View {
        RootView()
            .environmentObject(appState)
            .environment(\.locale, interfaceLocale)
            .preferredColorScheme(.light)
            .frame(minWidth: 1080, minHeight: 680)
            .background(WindowRestorationDisabler())
    }
}

@MainActor
private final class PersonalPiAppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var fallbackWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let application = notification.object as? NSApplication else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak application] in
            guard let self, let application else { return }
            self.ensureMainWindow(in: application)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            ensureMainWindow(in: sender)
        }
        return true
    }

    private func ensureMainWindow(in application: NSApplication) {
        if let existingWindow = application.windows.first(where: { $0.canBecomeMain }) {
            existingWindow.isRestorable = false
            if !existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
                activate(application)
            }
            return
        }

        let hostingController = NSHostingController(
            rootView: PersonalPiRootContainer(appState: appState)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Personal Pi"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 1080, height: 680)
        window.setContentSize(NSSize(width: 1240, height: 800))
        window.isRestorable = false
        window.center()

        let controller = NSWindowController(window: window)
        fallbackWindowController = controller
        controller.showWindow(nil)
        activate(application)
    }

    private func activate(_ application: NSApplication) {
        if #available(macOS 14.0, *) {
            application.activate()
        } else {
            application.activate(ignoringOtherApps: true)
        }
    }
}

private struct WindowRestorationDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        RestorationDisablingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.isRestorable = false
    }
}

private final class RestorationDisablingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isRestorable = false
    }
}
