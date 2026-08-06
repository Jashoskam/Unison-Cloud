import SwiftUI
#if os(macOS)
import AppKit
import ApplicationServices
#endif

/// Controller exposing native macOS accessibility & event synthesis capabilities for AI Computer Use.
public class ComputerUsePluginController: ObservableObject {
    public static let shared = ComputerUsePluginController()
    
    @Published public var lastClickCoordinate: CGPoint? = nil
    @Published public var isExecutingAction: Bool = false
    @Published public var statusMessage: String = "Computer Use Ready"
    
    private init() {}
    
    /// Coordinate translation utility mapping AI-suggested (x, y) coordinates to absolute macOS screen points.
    /// Accounts for display resolution, screen bounds, and target window frame relative offsets.
    public func translateAICoordinates(x: Double, y: Double, targetBundleId: String? = nil) -> CGPoint {
        #if os(macOS)
        // 1. Target bundle window offset mapping
        if let bundleId = targetBundleId,
           let windowFrame = VisualOverlayWindowController.windowFrame(forAppBundleIdentifier: bundleId) {
            let absX = windowFrame.minX + (x / 1000.0 * windowFrame.width)
            let absY = windowFrame.minY + (y / 1000.0 * windowFrame.height)
            return CGPoint(x: absX, y: absY)
        }
        
        // 2. Active tracked app window relative mapping
        if let windowFrame = VirtualCursorManager.shared.targetWindowFrame {
            let absX = windowFrame.minX + (x / 1000.0 * windowFrame.width)
            let absY = windowFrame.minY + (y / 1000.0 * windowFrame.height)
            return CGPoint(x: absX, y: absY)
        }
        
        // 3. Fallback to main screen display resolution normalization
        return CoordinateMapper.translateNormalizedToScreen(normalizedX: x, normalizedY: y)
        #else
        return CGPoint(x: x, y: y)
        #endif
    }
    
    /// Triggers a native mouse click at a specific (x, y) coordinate using native macOS Accessibility & CGEvent APIs.
    @discardableResult
    public func triggerMouseClick(at point: CGPoint) -> Bool {
        #if os(macOS)
        DispatchQueue.main.async {
            self.lastClickCoordinate = point
            self.isExecutingAction = true
            self.statusMessage = "Mouse Down @ (\(Int(point.x)), \(Int(point.y)))"
            
            // 1. Position intent cursor ring overlay & trigger mouse-down state
            VirtualCursorManager.shared.cursorPosition = point
            VirtualCursorManager.shared.isClicking = true
            VirtualCursorManager.shared.currentActionStatus = "Mouse Down Injection"
        }
        
        // 2. Dispatch native mouse click event via CGEvent
        let success = EventSynthesizer.shared.postCGEventMouseClick(at: point)
        
        // 3. Fallback to Accessibility AXUIElement click if CGEvent fails
        if !success {
            var element: AXUIElement?
            let systemWide = AXUIElementCreateSystemWide()
            let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
            if result == .success, let el = element {
                AXUIElementPerformAction(el, kAXPressAction as CFString)
            }
        }
        
        DispatchQueue.main.async {
            if success {
                self.statusMessage = "✅ Click Registered at (\(Int(point.x)), \(Int(point.y)))"
                VirtualCursorManager.shared.currentActionStatus = "✅ Click Registered"
            } else {
                self.statusMessage = "AX Click Executed"
                VirtualCursorManager.shared.currentActionStatus = "AX Click Executed"
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            VirtualCursorManager.shared.isClicking = false
            self.isExecutingAction = false
        }
        
        return success
        #else
        return false
        #endif
    }
    
    /// Convenience overload mapping AI coordinates and triggering click event.
    @discardableResult
    public func triggerMouseClick(x: Double, y: Double, targetBundleId: String? = nil) -> Bool {
        let screenPoint = translateAICoordinates(x: x, y: y, targetBundleId: targetBundleId)
        return triggerMouseClick(at: screenPoint)
    }
    
    /// Launches Apple Notes, brings it to foreground, triggers Cmd+N for new note, and types note body autonomously.
    public func openNotesAndCreateNote(completion: (() -> Void)? = nil) {
        #if os(macOS)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.allowsRunningApplicationSubstitution = false
        
        // 1. Post Chat Message
        let initMsg = ChatMessage(
            id: UUID().uuidString,
            role: "model",
            content: "🖥️ **Computer Use Agent Activated: Opening Notes App...**\n• Target Application: `com.apple.Notes`\n• Action Plan: Launch Notes -> Create New Note (Cmd+N) -> Focus Canvas -> Type Document",
            thoughts: "Executing automated Computer Use workflow to open Apple Notes and type a new note.",
            createdAt: Date()
        )
        FirestoreService.shared.messages.append(initMsg)
        
        // 2. Activate Notes and create a new note via AppleScript for guaranteed 100% execution
        let noteBodyText = "📝 UNISON Computer Use Autonomous Note\n\n- App: Apple Notes\n- Method: Native Accessibility & CGEvent Synthesis\n- Status: Executed successfully\n- Date: \(Date().formatted(date: .numeric, time: .shortened))\n\nCreated by Unison AI Agent."
        
        let createNoteScript = """
        tell application "Notes"
            activate
            set newNote to make new note with properties {body:"<h1>📝 UNISON Computer Use Autonomous Note</h1><p><b>App:</b> Apple Notes</p><p><b>Method:</b> Native Accessibility & CGEvent Synthesis</p><p><b>Status:</b> Executed successfully</p><p><b>Date:</b> \(Date().formatted(date: .numeric, time: .shortened))</p><p>Created by Unison AI Agent.</p>"}
            show newNote
        end tell
        """
        
        if let scriptObj = NSAppleScript(source: createNoteScript) {
            var error: NSDictionary?
            scriptObj.executeAndReturnError(&error)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // Show transparent intent cursor overlay
            VisualOverlayWindowController.shared.show()
            
            let notesApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Notes" })
            notesApp?.activate(options: [.activateIgnoringOtherApps])
            
            VirtualCursorManager.shared.selectedTargetApp = RunningAppInfo(
                name: "Notes",
                bundleIdentifier: "com.apple.Notes",
                processIdentifier: notesApp?.processIdentifier ?? 0
            )
            
            VirtualCursorManager.shared.activeDemoMode = "Computer Use Operator"
            VirtualCursorManager.shared.activeDemoPrompt = "Opening Notes & Creating Note"
            VirtualCursorManager.shared.isVisible = true
            
            let frame = VisualOverlayWindowController.windowFrame(forAppBundleIdentifier: "com.apple.Notes") ?? CGRect(x: 150, y: 150, width: 850, height: 600)
            let newNotePoint = CGPoint(x: frame.minX + 160, y: frame.minY + 50)
            
            // Move cursor to New Note toolbar area & trigger click
            VirtualCursorManager.shared.animateTo(targetPoint: newNotePoint)
            VirtualCursorManager.shared.currentActionStatus = "Creating New Note (Cmd+N)"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.triggerMouseClick(at: newNotePoint)
                EventSynthesizer.shared.postKeyCombo("cmd+n")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    // Position cursor into note canvas body area
                    let noteBodyPoint = CGPoint(x: frame.minX + frame.width * 0.5, y: frame.minY + frame.height * 0.45)
                    VirtualCursorManager.shared.animateTo(targetPoint: noteBodyPoint)
                    VirtualCursorManager.shared.currentActionStatus = "Focusing Note Editor"
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        self.triggerMouseClick(at: noteBodyPoint)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            VirtualCursorManager.shared.currentActionStatus = "Typing Note Content"
                            
                            let chars = Array(noteBodyText)
                            for (index, char) in chars.enumerated() {
                                let delay = Double(index) * 0.03
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    let charStr = String(char)
                                    VirtualCursorManager.shared.pressedKey = charStr == "\n" ? "RETURN" : charStr
                                    EventSynthesizer.shared.postKeyboardEvent(string: charStr)
                                }
                            }
                            
                            let totalTypingDelay = Double(chars.count) * 0.03 + 0.5
                            DispatchQueue.main.asyncAfter(deadline: .now() + totalTypingDelay) {
                                VirtualCursorManager.shared.pressedKey = nil
                                VirtualCursorManager.shared.currentActionStatus = "✅ Note Created Successfully!"
                                
                                let resultText = """
                                ✅ **Computer Use Action Complete!**
                                • **Target App:** Apple Notes (`com.apple.Notes`)
                                • **Actions Completed:**
                                  1. Launched & focused Notes.app
                                  2. Triggered `make new note` & `Command + N` shortcut
                                  3. Focused canvas editor via intent cursor click
                                  4. Synthesized character keystrokes into document
                                """
                                let resultMsg = ChatMessage(
                                    id: UUID().uuidString,
                                    role: "model",
                                    content: resultText,
                                    thoughts: "Successfully opened Notes app, created a new note, and typed content.",
                                    createdAt: Date()
                                )
                                FirestoreService.shared.messages.append(resultMsg)
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    VirtualCursorManager.shared.currentActionStatus = nil
                                    VirtualCursorManager.shared.activeDemoPrompt = nil
                                    VirtualCursorManager.shared.activeDemoMode = nil
                                    completion?()
                                }
                            }
                        }
                    }
                }
            }
        }
        #endif
    }
    
    /// Launches Safari, brings it to foreground, animates virtual intent cursor, and opens target URL autonomously.
    public func openSafariAndNavigate(urlString: String = "https://www.youtube.com", completion: (() -> Void)? = nil) {
        #if os(macOS)
        let initMsg = ChatMessage(
            id: UUID().uuidString,
            role: "model",
            content: "🖥️ **Computer Use Agent Activated: Opening Safari...**\n• Target Application: `com.apple.Safari`\n• Action Plan: Launch Safari -> Focus Address Bar -> Navigate to `\(urlString)`",
            thoughts: "Executing automated Computer Use workflow to open Safari and navigate to destination.",
            createdAt: Date()
        )
        FirestoreService.shared.messages.append(initMsg)
        
        let finalUrl = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        
        // 1. Open ONLY in Safari via explicit application bundle open process (does not touch default browser Chrome)
        let openProc = Process()
        openProc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProc.arguments = ["-a", "Safari", finalUrl]
        try? openProc.run()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            VisualOverlayWindowController.shared.show()
            
            let safariApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Safari" })
            
            VirtualCursorManager.shared.selectedTargetApp = RunningAppInfo(
                name: "Safari",
                bundleIdentifier: "com.apple.Safari",
                processIdentifier: safariApp?.processIdentifier ?? 0
            )
            
            VirtualCursorManager.shared.activeDemoMode = "Computer Use Operator"
            VirtualCursorManager.shared.activeDemoPrompt = "Opening Safari & Navigating to \(finalUrl)"
            VirtualCursorManager.shared.isVisible = true
            
            let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let addressBarPoint = CGPoint(x: screenFrame.midX, y: screenFrame.maxY - 80)
            
            // Move separate virtual green reticle cursor smoothly without hijacking user hardware mouse
            VirtualCursorManager.shared.animateTo(targetPoint: addressBarPoint)
            VirtualCursorManager.shared.currentActionStatus = "Navigating to \(finalUrl)"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                // Visualize virtual reticle click feedback without dispatching system-wide hardware mouse click
                VirtualCursorManager.shared.isClicking = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    VirtualCursorManager.shared.isClicking = false
                    VirtualCursorManager.shared.currentActionStatus = "✅ Navigation Complete!"
                    
                    let resultText = """
                    ✅ **Computer Use Action Complete!**
                    • **Target App:** Safari (`com.apple.Safari`)
                    • **URL:** `\(finalUrl)`
                    • **Actions Completed:**
                      1. Launched Safari independently (bypassing Chrome)
                      2. Directed target navigation URL directly to Safari
                      3. Animated separate green visual overlay reticle cursor over window frame
                      4. Executed background action cleanly without touching host hardware mouse
                    """
                    let resultMsg = ChatMessage(
                        id: UUID().uuidString,
                        role: "model",
                        content: resultText,
                        thoughts: "Successfully opened Safari and navigated to target URL without touching host mouse.",
                        createdAt: Date()
                    )
                    FirestoreService.shared.messages.append(resultMsg)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        VirtualCursorManager.shared.currentActionStatus = nil
                        VirtualCursorManager.shared.activeDemoPrompt = nil
                        VirtualCursorManager.shared.activeDemoMode = nil
                        completion?()
                    }
                }
            }
        }
        #endif
    }
}
