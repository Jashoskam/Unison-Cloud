import SwiftUI
#if os(macOS)
import AppKit

struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.makeKeyAndOrderFront(nil)
                window.makeKey()
                NSApp.activate(ignoringOtherApps: true)
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

extension View {
    @ViewBuilder
    func applyMacWindowStyling() -> some View {
        #if os(macOS)
        self.background(
            WindowAccessor { window in
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = false
                window.backgroundColor = .clear
                window.acceptsMouseMovedEvents = true
                window.level = .normal
                if let screen = window.screen ?? NSScreen.main {
                    window.setFrame(screen.visibleFrame, display: true, animate: true)
                }
                window.makeKeyAndOrderFront(nil)
                window.makeKey()
                NSApp.activate(ignoringOtherApps: true)
            }
        )
        #else
        self
        #endif
    }
}

@main
struct UnisonOSApp: App {
    // Inject service lifecycle as StateObject so it stays active through background routines
    @StateObject private var db = FirestoreService.shared
    @StateObject private var overlayService = SystemOverlayService.shared
    @StateObject private var audioService = NativeAudioService.shared
    
    init() {
        UserDefaults.standard.register(defaults: ["bypassPermissionChecks": true])
        #if os(macOS)
        DispatchQueue.main.async {
            NSApp?.setActivationPolicy(.regular)
            NSApp?.activate(ignoringOtherApps: true)
            if let logoImg = NSImage(contentsOfFile: "/Users/jashoskam/Desktop/Unison-ES/Unison/appLogo.png") {
                NSApp?.applicationIconImage = logoImg
            }
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            _ = CGRequestScreenCaptureAccess()
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if db.isAuthenticated {
                    DesktopView()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    LoginView()
                        .transition(.opacity)
                }
            }
            .applyMacWindowStyling()
            .animation(.easeInOut(duration: 0.35), value: db.isAuthenticated)
            .preferredColorScheme(.dark)
            .onAppear {
                #if os(macOS)
                NSApp.activate(ignoringOtherApps: true)
                Task { @MainActor in
                    overlayService.configure()
                    overlayService.refreshAccessibilityContext()
                }
                #endif
            }
            .onDisappear {
                #if os(macOS)
                overlayService.hideSpotlight()
                #endif
            }
        }
        .windowStyle(.hiddenTitleBar)
    }
}


