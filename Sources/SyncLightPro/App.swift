import SwiftUI
import AppKit

@main
struct SyncLightProApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            Button(model.l10n.openWindow) {
                openWindow(id: "main")
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button(model.l10n.quit) { NSApp.terminate(nil) }
        } label: {
            MenuBarIcon(isConnected: model.isConnected)
                .onAppear {
                    model.refreshStartOnBoot()
                    // Auto-connect the light that was in use last session.
                    model.autoConnectLastLight()
                    // Only pop the window on a normal (user-initiated) launch.
                    // When the app was started as a login item it should stay
                    // menu-bar-only; open the controls from the menu bar.
                    if !appDelegate.wasLaunchedAsLoginItem {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    } else {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
        }

        // The full control window (shown on launch, re-openable from the menu bar).
        Window(model.l10n.appTitle, id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 560)
                .background(WindowAccessor { window in
                    window?.delegate = appDelegate
                })
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

/// Custom menu-bar icon from `Resources/menu bar.png` (bundled as
/// `menu bar.png`). Falls back to an SF Symbol if the image is missing.
/// Dimmed when the light is not connected, full when connected.
struct MenuBarIcon: View {
    let isConnected: Bool

    /// Menu-bar glyph built from the bundled `menu bar.png`.
    ///
    /// Kept deliberately simple and crash-free: load the transparent PNG,
    /// normalise its size to the menu-bar glyph height, and mark it a template
    /// image so macOS tints it (black/white) to match the bar. The PNG already
    /// has a real transparent background (outer alpha = 0), so there is no
    /// black box. If anything fails we simply return nil and the view falls
    /// back to an SF Symbol — the status item is never empty.
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "menu bar", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }

        let targetH: CGFloat = 18   // standard menu-bar glyph height
        let src = img.size
        guard src.width > 0, src.height > 0 else { return nil }
        let aspect = src.width / src.height

        // Copy into a fixed-size image so SwiftUI/menu bar renders it 1:1.
        let newSize = NSSize(width: targetH * aspect, height: targetH)
        let out = NSImage(size: newSize)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        img.draw(in: NSRect(origin: .zero, size: newSize),
                 from: NSRect(origin: .zero, size: src),
                 operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        out.isTemplate = true
        return out
    }()

    var body: some View {
        if let img = MenuBarIcon.image {
            Image(nsImage: img)
                .renderingMode(.template)   // theme-tinted, full strength
                .accessibilityLabel("SyncLight Pro")
        } else {
            Image(systemName: isConnected ? "lightbulb.fill" : "lightbulb")
        }
    }
}

/// Captures the hosting NSWindow so we can observe its close.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onWindow(v.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Shows a Dock icon while the controls window is open, and hides it (menu-bar
/// only) once the window is closed. The app keeps running in the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    /// True only when macOS started us as a login item (Start on boot). Set from
    /// the default-launch flag so that manually opening the app (Dock/Finder)
    /// always shows the window even if "Start on boot" is enabled.
    private(set) var wasLaunchedAsLoginItem = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Distinguish a real login-item launch from a user launch.
        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) ?? true
        let startOnBoot = UserDefaults.standard.bool(forKey: "startOnBoot")
        wasLaunchedAsLoginItem = startOnBoot && !isDefaultLaunch

        // Login-item launch → menu-bar-only. Otherwise a normal, windowed app.
        NSApp.setActivationPolicy(wasLaunchedAsLoginItem ? .accessory : .regular)
    }

    /// Clicking the Dock icon (or re-opening) should always surface the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.setActivationPolicy(.regular)
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Window closed → drop to menu-bar-only (no Dock icon) and keep running.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
