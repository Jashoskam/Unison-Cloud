import Foundation
import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
import ApplicationServices
import UserNotifications
import Carbon
#endif

#if os(macOS)
@MainActor
public final class SystemOverlayService: ObservableObject {
    public static let shared = SystemOverlayService()

    @Published public var isMenuBarEnabled: Bool = false
    @Published public var isSpotlightVisible: Bool = false
    @Published public var statusText: String = "Overlay ready"
    @Published public var activeApplicationName: String = "Waiting for focus"
    @Published public var activeWindowTitle: String = ""
    @Published public var selectedText: String = ""
    @Published public var accessibilitySummary: String = ""

    private var statusItem: NSStatusItem?
    private var spotlightWindow: NSWindow?
    private var globalEventMonitor: Any?
    private var isConfigured = false

    private init() {}

    private var realtimeTimer: Timer?

    public func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        installStatusBarItem()
        startGlobalHotkeyMonitoring()
        refreshAccessibilityContext()
        startRealtimeContextMonitoring()
    }

    public func startRealtimeContextMonitoring() {
        realtimeTimer?.invalidate()
        realtimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibilityContext()
            }
        }
    }

    public func installStatusBarItem() {
        let statusBar = NSStatusBar.system
        let item = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Unison OS Menu Bar")
            button.target = self
            button.action = #selector(toggleSpotlightFromMenuBar)
        }
        statusItem = item
        isMenuBarEnabled = true
        statusText = "Menu bar overlay active"
        
        // Request System Notification Access safely if bundle ID is set
        #if os(macOS)
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
        #endif
    }
    
    public func sendNotification(title: String = "Unison OS", body: String = "Task completed successfully.") {
        #if os(macOS)
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
        #endif
    }

    public func teardown() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        hideSpotlight()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        isMenuBarEnabled = false
    }

    public func refreshAccessibilityContext() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        activeApplicationName = frontmost?.localizedName ?? "No active app"

        var windowTitle: String = ""
        if let app = frontmost {
            windowTitle = self.windowTitle(for: app)
        }
        activeWindowTitle = windowTitle

        let selected = extractSelectedText()
        selectedText = selected

        let summary = buildAccessibilitySummary(appName: activeApplicationName, windowTitle: activeWindowTitle, selectedText: selected)
        accessibilitySummary = summary
        statusText = "Context refreshed • \(activeApplicationName)"
    }

    public func showSpotlight() {
        if spotlightWindow == nil {
            createSpotlightWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        spotlightWindow?.makeKeyAndOrderFront(nil)
        spotlightWindow?.orderFrontRegardless()
        isSpotlightVisible = true
        statusText = "Spotlight overlay active"
        refreshAccessibilityContext()
    }

    public func hideSpotlight() {
        spotlightWindow?.orderOut(nil)
        isSpotlightVisible = false
    }

    @objc private func toggleSpotlightFromMenuBar() {
        toggleSpotlight()
    }

    private var lastToggleTimestamp: TimeInterval = 0

    public func toggleSpotlight() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastToggleTimestamp > 0.35 else { return }
        lastToggleTimestamp = now
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isSpotlightVisible {
                self.hideSpotlight()
            } else {
                self.showSpotlight()
            }
        }
    }

    private func createSpotlightWindow() {
        let frame = NSRect(x: 0, y: 0, width: 540, height: 220)
        let panel = NSPanel(contentRect: frame, styleMask: [.titled, .fullSizeContentView, .utilityWindow], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false

        let hostingView = NSHostingView(rootView: SpotlightOverlayView(service: self))
        hostingView.frame = panel.contentRect(forFrameRect: frame)
        panel.contentView = hostingView

        let screenVisibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowRect = NSRect(
            x: screenVisibleFrame.maxX - frame.width - 20,
            y: screenVisibleFrame.maxY - frame.height - 10,
            width: frame.width,
            height: frame.height
        )
        panel.setFrame(windowRect, display: true)
        spotlightWindow = panel
    }

    private func startGlobalHotkeyMonitoring() {
        #if os(macOS)
        guard globalEventMonitor == nil else { return }
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isOptionSpace = flags.contains(.option) && (event.keyCode == 49 || event.charactersIgnoringModifiers == " ")
            if isOptionSpace {
                self.toggleSpotlight()
            }
        }
        
        _ = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isOptionSpace = flags.contains(.option) && (event.keyCode == 49 || event.charactersIgnoringModifiers == " ")
            if isOptionSpace {
                self.toggleSpotlight()
                return nil
            }
            return event
        }
        #endif
    }

    private func windowTitle(for app: NSRunningApplication) -> String {
        let systemElement = AXUIElementCreateSystemWide()
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        if result == .success, let focusedWindowRef = focusedWindow {
            let windowValue = focusedWindowRef as! AXUIElement
            var title: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(windowValue, kAXTitleAttribute as CFString, &title)
            if titleResult == .success, let titleValue = title as? String {
                return titleValue
            }
        }

        if let name = app.localizedName {
            return name
        }
        return ""
    }

    private func extractSelectedText() -> String {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let copyFocused = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard copyFocused == .success, let focusedElementRef = focusedElement else {
            return ""
        }
        let element = focusedElementRef as! AXUIElement

        var selectedText: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        if selectedResult == .success, let text = selectedText as? String, !text.isEmpty {
            return text
        }

        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        if valueResult == .success, let textValue = value as? String, !textValue.isEmpty {
            return textValue
        }

        return ""
    }

    public func requestAllSystemPermissions() {
        #if os(macOS)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if #available(macOS 10.15, *) {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
        }
        
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        
        SpeechRecognizer.shared.requestPermissions()
        #endif
    }

    private func buildAccessibilitySummary(appName: String, windowTitle: String, selectedText: String) -> String {
        var parts: [String] = ["App: \(appName)"]
        if !windowTitle.isEmpty { parts.append("Window: \(windowTitle)") }
        if !selectedText.isEmpty { parts.append("Selection: \(selectedText.prefix(120))") }
        return parts.joined(separator: " • ")
    }
}

public struct SpotlightOverlayView: View {
    @ObservedObject var service: SystemOverlayService
    @State private var inputPrompt: String = ""
    @State private var isAccessibilityGranted: Bool = true
    @ObservedObject var speech: SpeechRecognizer = SpeechRecognizer.shared

    public var body: some View {
        VStack(spacing: 12) {
            // 1. Prominent 180x180 Glowing Celestial Gemini Live AI Orb
            VStack(spacing: 12) {
                Button(action: {
                    // Interruption handling: stop any ongoing AI TTS speech immediately
                    SpeechManager.shared.stop()
                    
                    if speech.isListening {
                        speech.stopListening()
                    } else {
                        speech.startListening()
                    }
                }) {
                    UnisonAIEnergyOrb(isRecording: speech.isListening, size: 180.0)
                        .shadow(color: Color.cyan.opacity(speech.isListening ? 0.6 : 0.3), radius: 24, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .help("Tap Gemini Live Orb to speak or listen in real-time")
                
                HStack(spacing: 6) {
                    Image(systemName: speech.isListening ? "waveform.circle.fill" : "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(speech.isListening ? .cyan : .purple)
                    
                    Text(speech.isListening ? "Gemini Live Active • Listening..." : "Option + Space • Tap Orb to Speak Live")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(speech.isListening ? .cyan : .white.opacity(0.75))
                }
                
                if let err = speech.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(err)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Button(action: { speech.errorMessage = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red, lineWidth: 1))
                }
            }
            .padding(.top, 8)

            // 2. Permission Banner if needed
            if !isAccessibilityGranted {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.yellow)
                    Text("macOS Permissions required for background desktop control.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Button(action: {
                        service.requestAllSystemPermissions()
                    }) {
                        Text("Grant Access")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.yellow)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.12))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
            }

            // 3. Quick Prompt Input Bar (Under macOS Menu Bar)
            SpotlightInputBar(service: service, inputPrompt: $inputPrompt)
        }
        .padding(14)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 8)
        .onReceive(speech.$transcript) { text in
            if !text.isEmpty {
                self.inputPrompt = text
            }
        }
        .onAppear {
            service.requestAllSystemPermissions()
            #if os(macOS)
            isAccessibilityGranted = AXIsProcessTrusted()
            #endif
            speech.onSilenceDetected = { _ in
                if !self.inputPrompt.isEmpty {
                    let text = self.inputPrompt
                    self.inputPrompt = ""
                    self.speech.stopListening()
                    FirestoreService.shared.sendVoicePromptToGeminiLive(prompt: text)
                }
            }
        }
    }
}

public struct SpotlightInputBar: View {
    @ObservedObject var service: SystemOverlayService
    @Binding var inputPrompt: String

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.4))
            
            TextField("Ask Unison AI or type computer use command...", text: $inputPrompt)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13))
                .foregroundColor(.white)
                .onSubmit {
                    submitQuery()
                }
            
            Button(action: { submitQuery() }) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(inputPrompt.isEmpty ? .white.opacity(0.2) : .cyan)
            }
            .buttonStyle(.plain)
            .disabled(inputPrompt.isEmpty)
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func submitQuery() {
        if !inputPrompt.isEmpty {
            let query = inputPrompt
            inputPrompt = ""
            service.hideSpotlight()
            AgentStateController.shared.agentQuery = query
            AgentStateController.shared.startLoop()
        }
    }
}
#else
public final class SystemOverlayService: ObservableObject {
    public static let shared = SystemOverlayService()
    @Published public var isMenuBarEnabled: Bool = false
    @Published public var isSpotlightVisible: Bool = false
    @Published public var statusText: String = "Overlay ready"
    @Published public var activeApplicationName: String = ""
    @Published public var activeWindowTitle: String = ""
    @Published public var selectedText: String = ""
    @Published public var accessibilitySummary: String = ""

    private init() {}
    public func configure() {}
    public func refreshAccessibilityContext() {}
    public func showSpotlight() {}
    public func hideSpotlight() {}
    public func toggleSpotlight() {}
}
#endif
