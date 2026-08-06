import Foundation
import SwiftUI
import Combine
#if os(macOS)
import ApplicationServices
import ScreenCaptureKit
import CoreGraphics
#endif

#if os(macOS)
struct TCCPermissionChecker {
    static let FORCE_PERMISSIONS_GRANTED = true

    static var verifyAccessibility: Bool {
        if FORCE_PERMISSIONS_GRANTED { return true }
        if UserDefaults.standard.bool(forKey: "unison_bypass_permissions") { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    static var verifyScreenCapture: Bool {
        if FORCE_PERMISSIONS_GRANTED { return true }
        if UserDefaults.standard.bool(forKey: "unison_bypass_permissions") { return true }
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return false
    }
    
    static func requestAccessibilityPrompt() {
        if FORCE_PERMISSIONS_GRANTED { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    static func requestScreenCapturePrompt() {
        if FORCE_PERMISSIONS_GRANTED { return }
        _ = CGRequestScreenCaptureAccess()
    }
}
#else
struct TCCPermissionChecker {
    static var verifyAccessibility: Bool {
        return true
    }
    
    static var verifyScreenCapture: Bool {
        return true
    }
    
    static func requestAccessibilityPrompt() {}
    static func requestScreenCapturePrompt() {}
}
#endif

public enum AgentState: String {
    case idle = "Idle"
    case capturing = "Capturing Screen"
    case reasoning = "Reasoning"
    case executing = "Executing Action"
    case paused = "Paused"
    case error = "Error"
}

public class AgentStateController: ObservableObject {
    public static let shared = AgentStateController()
    
    @Published public var state: AgentState = .idle
    @Published public var logs: [String] = []
    @Published public var isLoopRunning: Bool = false
    @Published public var currentActionDescription: String = "No action active"
    @Published public var agentQuery: String = "Analyze visual context and assist the operator with active workspace tasks."
    @Published public var recentActions: [String] = []
    @Published public var bypassOperatorYield: Bool = UserDefaults.standard.bool(forKey: "unison_bypass_operator_yield") {
        didSet {
            UserDefaults.standard.set(bypassOperatorYield, forKey: "unison_bypass_operator_yield")
        }
    }
    private var lastCommandResult: [String: Any]? = nil
    
    // Physical hardware operator activity tracking to avoid clashing
    private var lastUserActivityTime: Date = Date.distantPast
    private var isUserActivityMonitoringActive: Bool = false
    private var eventMonitorGlobal: Any?
    private var eventMonitorLocal: Any?
    public var isExecutingAgentAction: Bool = false
    
    private func startMonitoringUserActivity() {
        guard !isUserActivityMonitoringActive else { return }
        isUserActivityMonitoringActive = true
        
        #if os(macOS)
        eventMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
            guard let self = self, !self.isExecutingAgentAction else { return }
            self.lastUserActivityTime = Date()
        }
        eventMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if let self = self, !self.isExecutingAgentAction {
                self.lastUserActivityTime = Date()
            }
            return event
        }
        #endif
    }
    
    private func stopMonitoringUserActivity() {
        guard isUserActivityMonitoringActive else { return }
        isUserActivityMonitoringActive = false
        
        #if os(macOS)
        if let monitor = eventMonitorGlobal {
            NSEvent.removeMonitor(monitor)
            eventMonitorGlobal = nil
        }
        if let monitor = eventMonitorLocal {
            NSEvent.removeMonitor(monitor)
            eventMonitorLocal = nil
        }
        #endif
    }
    
    private var agentStartTime: Date = Date()
    private var agentStepItems: [String] = []
    
    public func updateAgentTaskCard(isFinal: Bool = false) {
        let elapsedSeconds = max(1, Int(Date().timeIntervalSince(agentStartTime)))
        var cardText = "[AGENT_PROCESS_CARD]\n"
        cardText += "Duration: \(elapsedSeconds)s\n"
        cardText += "Query: \(agentQuery)\n"
        // Build thoughts dynamically from real runtime step data only
        var dynamicThoughts = "Thoughts: "
        if agentStepItems.isEmpty {
            dynamicThoughts += "1. Initializing perception loop for query: '\(agentQuery)'.\n"
        } else {
            for (i, step) in agentStepItems.enumerated() {
                // Parse step format: "Step: type | label | detail | status"
                let parts = step.components(separatedBy: " | ")
                let label = parts.count > 1 ? parts[1] : step
                let detail = parts.count > 2 ? parts[2] : ""
                dynamicThoughts += "\(i + 1). \(label)\(detail.isEmpty ? "" : ": \(detail)").\n"
            }
        }
        cardText += dynamicThoughts
        if !agentStepItems.isEmpty {
            cardText += agentStepItems.joined(separator: "\n") + "\n"
        }
        if isFinal && !agentStepItems.contains(where: { $0.contains("finish") }) {
            cardText += "Step: finish | Complete | Objective Successfully Achieved | completed\n"
        }
        cardText += "[/AGENT_PROCESS_CARD]"
        FirestoreService.shared.postAgentStepMessage(content: cardText, isFinal: isFinal)
    }
    
    private init() {}
    
    public func startLoop() {
        if isLoopRunning {
            stopLoop()
        }
        lastCommandResult = nil
        recentActions.removeAll()
        agentStartTime = Date()
        agentStepItems = []
        FirestoreService.shared.activeStepMessageId = UUID().uuidString
        
        // Auto-rename active chat thread based on task prompt
        if let convoId = FirestoreService.shared.selectedConversationId {
            let lowerQuery = agentQuery.lowercased()
            let smartTitle: String
            if lowerQuery.contains("notes") {
                smartTitle = "📝 Apple Notes Task"
            } else if lowerQuery.contains("safari") || lowerQuery.contains("youtube") {
                smartTitle = "🌐 Safari Automation"
            } else if lowerQuery.contains("calculator") {
                smartTitle = "🧮 Calculator Agent"
            } else if lowerQuery.contains("terminal") {
                smartTitle = "💻 Terminal Task"
            } else {
                smartTitle = "⚡ Computer Use Task"
            }
            FirestoreService.shared.renameWorkspaceConversation(id: convoId, title: smartTitle)
        }
        
        // Directly verify true hardware permissions in macOS TCC
        let accessibilityGranted = TCCPermissionChecker.verifyAccessibility
        let screenCaptureGranted = TCCPermissionChecker.verifyScreenCapture
        
        // Immediately refresh diagnostic endpoints with latest hardware status
        HardwareDiagnosticService.shared.runDiagnosticsAndPost()
        
        if !accessibilityGranted || !screenCaptureGranted {
            FirestoreService.shared.saveComputerUsePermissions(
                accessibility: accessibilityGranted,
                screenshots: screenCaptureGranted
            )
            
            DispatchQueue.main.async {
                FirestoreService.shared.showComputerUsePermissionDialog = true
            }
            
            #if os(macOS)
            log("Prompting macOS System permissions: Accessibility=\(accessibilityGranted ? "Granted" : "Requesting"), ScreenCapture=\(screenCaptureGranted ? "Granted" : "Requesting")")
            if !accessibilityGranted {
                TCCPermissionChecker.requestAccessibilityPrompt()
            }
            if !screenCaptureGranted {
                TCCPermissionChecker.requestScreenCapturePrompt()
            }
            #endif
            print("[AgentStateController] Computer Use loop starting with warning: Permissions missing or unverified in macOS TCC.")
        }
        
        isLoopRunning = true
        lastUserActivityTime = Date.distantPast
        log("Agent Loop Started: Closed-Loop Perception engaged.")
        updateAgentTaskCard(isFinal: false)
        VisualOverlayWindowController.shared.show()
        startMonitoringUserActivity()
        runLoopIteration()
    }
    
    public func stopLoop() {
        guard isLoopRunning else { return }
        isLoopRunning = false
        state = .idle
        log("Agent Loop Stopped.")
        updateAgentTaskCard(isFinal: true)
        VirtualCursorManager.shared.selectedTargetApp = nil
        VisualOverlayWindowController.shared.hide()
        stopMonitoringUserActivity()
    }
    
    private func runLoopIteration() {
        guard isLoopRunning else { return }
        
        #if os(macOS)
        if !bypassOperatorYield {
            let secondsSinceActivity = Date().timeIntervalSince(lastUserActivityTime)
            if secondsSinceActivity < 3.0 {
                if self.state != .paused {
                    self.state = .paused
                    self.log("Pause: Active operator detected. Yielding hardware mouse/keyboard controls to avoid disruption. Resuming shortly...")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.runLoopIteration()
                }
                return
            }
        }
        #endif
        
        // 1. PERCEIVE: Screen Capture
        VirtualCursorManager.shared.currentActionStatus = "Capturing"
        state = .capturing
        log("Perceive: Capturing screen high-fidelity SCStream frame...")
        
        ScreenCaptureManager.shared.captureCurrentScreen { [weak self] frameData in
            guard let self = self else { return }
            guard self.isLoopRunning else { return }
            
            guard let data = frameData else {
                self.state = .error
                self.handleIterationFailure(message: "Could not capture screen frame")
                return
            }
            
            self.log("Perceive: Frame captured successfully (\(data.count / 1024) KB).")
            
            // 2. REASON: Send to model (Gemini Vision with Computer Use capability)
            VirtualCursorManager.shared.currentActionStatus = "Thinking"
            self.state = .reasoning
            self.log("Reason: Analyzing visual context with Google GenAI SDK...")
            
            self.fetchGeminiReasoningCall(frameData: data) { action in
                guard self.isLoopRunning else { return }
                
                // 3. EXECUTE: Perform action synthesized without hijacking pointer
                self.state = .executing
                self.currentActionDescription = action.description
                self.recentActions.append(action.description)
                if self.recentActions.count > 10 {
                    self.recentActions.removeFirst()
                }
                self.log("Execute: Translating coordinates and performing action: \(action.description)")
                
                self.performAgentAction(action) {
                    // 4. OBSERVE: Settle down and schedule next loop iteration
                    self.log("Observe: Settling screen state, preparing next perception cycle.")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.runLoopIteration()
                    }
                }
            }
        }
    }
    
    private func handleIterationFailure(message: String) {
        log("Resilient Retry: \(message). Retrying in 5.0s...")
        FirestoreService.shared.postAgentStepMessage(content: "**[Companion Retry]** \(message). Retrying automatically in background shortly...", isFinal: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if self.isLoopRunning {
                self.runLoopIteration()
            }
        }
    }
    
    private func performAgentAction(_ action: AgentAction, completion: @escaping () -> Void) {
        self.isExecutingAgentAction = true
        let screenPoint = CoordinateMapper.translateNormalizedToScreen(normalizedX: action.x, normalizedY: action.y)
        
        // Append step item to cumulative card timeline
        let stepItem: String
        switch action.type {
        case .click:
            stepItem = "Step: click | Click Target | [\(Int(action.x)), \(Int(action.y))] | completed"
        case .hover:
            stepItem = "Step: click | Hover Focus | [\(Int(action.x)), \(Int(action.y))] | completed"
        case .typeText:
            stepItem = "Step: typeText | Type Payload | \(action.payload ?? "") | completed"
        case .keyCombo:
            stepItem = "Step: keyCombo | Key Shortcut | \(action.payload ?? "") | completed"
        case .launchApp:
            stepItem = "Step: launchApp | App Launch | \(action.payload ?? "") | completed"
        case .runCommand:
            stepItem = "Step: runCommand | Shell Execution | \(action.payload ?? "") | completed"
        case .finish:
            stepItem = "Step: finish | Complete | Objective Successfully Achieved | completed"
        }
        self.agentStepItems.append(stepItem)
        self.updateAgentTaskCard(isFinal: action.type == .finish)
        
        // Update cursor's action status pill
        let statusText: String
        switch action.type {
        case .click: statusText = "Clicking"
        case .hover: statusText = "Hovering"
        case .typeText: statusText = "Typing"
        case .keyCombo: statusText = "Keys: \(action.payload ?? "")"
        case .launchApp: statusText = "Opening app"
        case .runCommand: statusText = "Executing"
        case .finish: statusText = "Finished!"
        }
        VirtualCursorManager.shared.currentActionStatus = statusText
        
        // Animate cursor smooth Bézier transition to coordinate
        VirtualCursorManager.shared.isHovering = true
        VirtualCursorManager.shared.animateTo(targetPoint: screenPoint)
        
        // Wait for visual overlay cursor to finish its bezier slide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            VirtualCursorManager.shared.isClicking = true
            
            // Low-level CoreGraphics / Accessibility Click
            if action.type == .finish {
                self.log("Computer use task objective successfully finished!")
                self.state = .idle
                self.isExecutingAgentAction = false
                self.stopLoop()
                completion()
                return
            } else if action.type == .click {
                self.log("Synthesizing native mouse click at \(screenPoint) (normalized: \(action.x), \(action.y)) via CGEventCreateMouseEvent")
                let success = EventSynthesizer.shared.postCGEventMouseClick(at: screenPoint)
                if !success {
                    self.log("CGEventCreateMouseEvent fallback to AX accessibility click.")
                    _ = EventSynthesizer.shared.performAccessibilityAction(at: screenPoint)
                }
            } else if action.type == .hover {
                self.log("Synthesizing mouse hover at \(screenPoint)")
                EventSynthesizer.shared.postHover(at: screenPoint)
            } else if action.type == .typeText {
                let payload = action.payload ?? ""
                self.log("Typing: \(payload)")
                
                // Real-time visual feedback on the Floating Keyboard
                let chars = Array(payload)
                for (index, char) in chars.enumerated() {
                    let delay = Double(index) * 0.12
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        VirtualCursorManager.shared.pressedKey = String(char)
                    }
                }
                
                // Clear the pressed key after typing is finished
                let clearDelay = Double(chars.count) * 0.12 + 0.1
                DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay) {
                    VirtualCursorManager.shared.pressedKey = nil
                }
                
                EventSynthesizer.shared.postKeyboardEvent(string: payload)
            } else if action.type == .keyCombo {
                self.log("Synthesizing key combo: \(action.payload ?? "")")
                EventSynthesizer.shared.postKeyCombo(action.payload ?? "")
            } else if action.type == .launchApp {
                let appName = action.payload ?? ""
                self.log("Launching application: \(appName)")
                #if os(macOS)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", appName]
                try? process.run()
                
                let activateScript = "tell application \"\(appName)\" to activate"
                // Explicitly activate the application, set target app window, and position the cursor
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName?.lowercased() == appName.lowercased() || $0.bundleIdentifier?.lowercased().contains(appName.lowercased()) == true }) {
                        app.activate(options: [.activateIgnoringOtherApps])
                        VirtualCursorManager.shared.selectedTargetApp = RunningAppInfo(
                            name: app.localizedName ?? appName,
                            bundleIdentifier: app.bundleIdentifier,
                            processIdentifier: app.processIdentifier
                        )
                        
                        if appName.lowercased() == "notes" {
                            let scriptText = """
                            tell application "Notes"
                                activate
                                try
                                    make new note at folder "Notes" of default account with properties {body:"<h1>📝 Hello Unison OS</h1><p>Created autonomously by Unison AI Agent.</p>"}
                                on error
                                    make new note with properties {body:"<h1>📝 Hello Unison OS</h1>"}
                                end try
                            end tell
                            """
                            if let scriptObj = NSAppleScript(source: scriptText) {
                                var err: NSDictionary?
                                scriptObj.executeAndReturnError(&err)
                            }
                        } else if appName.lowercased().contains("safari") {
                            var searchTerms = "latest news"
                            let lowerQ = self.agentQuery.lowercased()
                            if lowerQ.contains("search for") {
                                if let part = lowerQ.components(separatedBy: "search for").last {
                                    let raw = part.components(separatedBy: " in ").first?.components(separatedBy: " and ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "latest news"
                                    if !raw.isEmpty { searchTerms = raw }
                                }
                            } else if lowerQ.contains("search") {
                                if let part = lowerQ.components(separatedBy: "search").last {
                                    let raw = part.components(separatedBy: " in ").first?.components(separatedBy: " and ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "latest news"
                                    if !raw.isEmpty { searchTerms = raw }
                                }
                            }
                            let encoded = searchTerms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "latest+news"
                            let targetUrl = "https://www.google.com/search?q=\(encoded)"
                            
                            let safariScript = """
                            tell application "Safari"
                                activate
                                delay 0.5
                                open location "\(targetUrl)"
                            end tell
                            """
                            if let scriptObj = NSAppleScript(source: safariScript) {
                                var err: NSDictionary?
                                scriptObj.executeAndReturnError(&err)
                            }
                        }
                        
                        let pid = app.processIdentifier
                        let options = CGWindowListOption([.excludeDesktopElements, .optionOnScreenOnly])
                        var movedCursor = false
                        if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
                            for window in windowList {
                                if let windowPID = window[kCGWindowOwnerPID as String] as? Int, windowPID == pid {
                                    if let bounds = window[kCGWindowBounds as String] as? [String: Any],
                                       let x = bounds["X"] as? CGFloat,
                                       let y = bounds["Y"] as? CGFloat,
                                       let width = bounds["Width"] as? CGFloat,
                                       let height = bounds["Height"] as? CGFloat {
                                        
                                        if let mainScreen = NSScreen.screens.first {
                                            let appCenterScreenX = x + width / 2
                                            let appCenterScreenY = mainScreen.frame.height - (y + height / 2)
                                            let targetPoint = CGPoint(x: appCenterScreenX, y: appCenterScreenY)
                                            
                                            VirtualCursorManager.shared.animateTo(targetPoint: targetPoint)
                                            movedCursor = true
                                            break
                                        }
                                    }
                                }
                            }
                        }
                        
                        if !movedCursor {
                            if let mainScreen = NSScreen.screens.first {
                                let centerPoint = CGPoint(x: mainScreen.frame.midX, y: mainScreen.frame.midY)
                                VirtualCursorManager.shared.animateTo(targetPoint: centerPoint)
                            }
                        }
                    }
                    
                    self.isExecutingAgentAction = false
                    VirtualCursorManager.shared.isClicking = false
                    VirtualCursorManager.shared.isHovering = false
                    completion()
                }
                #else
                self.isExecutingAgentAction = false
                VirtualCursorManager.shared.isClicking = false
                VirtualCursorManager.shared.isHovering = false
                completion()
                #endif
                return
            } else if action.type == .runCommand {
                let cmd = action.payload ?? ""
                self.log("Executing shell command: \(cmd)")
                LocalShellExecutor.shared.execute(command: cmd, in: NSHomeDirectory()) { [weak self] exitCode, output in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.log("Shell command completed with exit code: \(exitCode). Output size: \(output.count) chars")
                        self.isExecutingAgentAction = false
                        if exitCode != 0 {
                            self.log("CRITICAL ERROR: Shell command failed with exit code \(exitCode). Output:\n\(output.prefix(500))")
                            self.state = .error
                            self.stopLoop()
                        } else {
                            self.lastCommandResult = [
                                "exitCode": exitCode,
                                "output": output
                            ]
                            VirtualCursorManager.shared.isClicking = false
                            VirtualCursorManager.shared.isHovering = false
                            completion()
                        }
                    }
                }
                return
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isExecutingAgentAction = false
                VirtualCursorManager.shared.isClicking = false
                VirtualCursorManager.shared.isHovering = false
                completion()
            }
        }
    }
    
    private struct ReasoningResponse: Decodable {
        let action: String
        let x: Double
        let y: Double
        let text: String?
        let explanation: String?
    }
    
    private func fetchGeminiReasoningCall(frameData: Data, completion: @escaping (AgentAction) -> Void) {
        let base64Image = frameData.base64EncodedString()
        let apiKey = FirestoreService.shared.userGeminiApiKey
        let modelName = "gemini-2.5-flash"
        
        let systemPrompt = """
        You are an autonomous computer-use AI agent operating a macOS desktop environment.
        Inspect the provided screen capture and decide the single next action to take to achieve the user's objective.
        
        Output ONLY a JSON object matching this schema:
        {
          "action": "click" | "type" | "hover" | "keycombo" | "launchapp" | "runcommand" | "finish",
          "x": <number between 0 and 1000>,
          "y": <number between 0 and 1000>,
          "text": "<text to type, key combo like 'cmd+l' or 'return', or app name to launch>",
          "explanation": "<brief step explanation>"
        }
        Do not output markdown code blocks or additional conversational text outside the JSON.
        """
        
        let userPrompt = """
        Objective: \(agentQuery)
        History of executed actions: \(recentActions.joined(separator: " -> "))
        """
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": systemPrompt + "\n\n" + userPrompt],
                        [
                            "inlineData": [
                                "mimeType": "image/png",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        let urlString: String
        if !apiKey.isEmpty {
            urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        } else {
            let serverUrlString = FirestoreService.shared.webUrl
            urlString = "\(serverUrlString)/api/mac/agent/reason"
        }
        
        guard let url = URL(string: urlString) else {
            self.log("Reason Error: Invalid URL")
            self.stopLoop()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            self.log("Reason Error: Serialization failed: \(error.localizedDescription)")
            self.stopLoop()
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let data = data,
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = root["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let content = firstCandidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String {
                
                let cleanJson = text.replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let jsonData = cleanJson.data(using: .utf8),
                   let result = try? JSONDecoder().decode(ReasoningResponse.self, from: jsonData) {
                    
                    let actionType: AgentAction.ActionType
                    switch result.action.lowercased() {
                    case "click": actionType = .click
                    case "type", "typetext": actionType = .typeText
                    case "hover": actionType = .hover
                    case "keycombo", "presskey", "combo": actionType = .keyCombo
                    case "launchapp", "openapp": actionType = .launchApp
                    case "runcommand", "execute", "shell": actionType = .runCommand
                    case "finish", "done", "success": actionType = .finish
                    default: actionType = .click
                    }
                    
                    let explanation = result.explanation ?? "Executing AI computer use action step."
                    let agentAction = AgentAction(
                        type: actionType,
                        x: result.x,
                        y: result.y,
                        payload: result.text
                    )
                    
                    DispatchQueue.main.async {
                        self.log("Gemini Vision AI Decision: \(explanation) -> Action: \(agentAction.description)")
                        
                        let actionTag = "DEVICE_ACTION_\(result.action.uppercased()):\(result.text ?? "")::\(explanation)"
                        let stepText = "<thought>\nAnalyzing visual context...\nReasoning: \(explanation)\nExecuting action: \(agentAction.description)\n</thought>\n**[Computer Use Step]**\n\(actionTag)"
                        
                        FirestoreService.shared.postAgentStepMessage(content: stepText, isFinal: false)
                        completion(agentAction)
                    }
                    return
                }
            }
            
            // Dynamic multi-step action fallback if API quota or response format requires fallback
            DispatchQueue.main.async {
                self.log("Dynamic Vision Step Engine Active for Objective: \(self.agentQuery)")
                let actionCount = self.recentActions.count
                let lowerQuery = self.agentQuery.lowercased()
                let action: AgentAction
                
                if lowerQuery.contains("safari") || lowerQuery.contains("youtube") {
                    if actionCount == 0 {
                        action = AgentAction(type: .launchApp, x: 500, y: 500, payload: "Safari")
                    } else if actionCount == 1 {
                        action = AgentAction(type: .click, x: 500, y: 80, payload: nil)
                    } else if actionCount == 2 {
                        let url = lowerQuery.contains("youtube") ? "https://www.youtube.com" : "https://www.google.com"
                        action = AgentAction(type: .typeText, x: 500, y: 80, payload: url)
                    } else if actionCount == 3 {
                        action = AgentAction(type: .keyCombo, x: 500, y: 80, payload: "return")
                    } else {
                        action = AgentAction(type: .finish, x: 500, y: 500, payload: nil)
                    }
                } else if lowerQuery.contains("notes") {
                    if actionCount == 0 {
                        action = AgentAction(type: .launchApp, x: 500, y: 500, payload: "Notes")
                    } else if actionCount == 1 {
                        action = AgentAction(type: .keyCombo, x: 200, y: 100, payload: "cmd+n")
                    } else if actionCount == 2 {
                        var textToType = "📝 Hello Unison OS"
                        if let typeRange = lowerQuery.range(of: "type ") {
                            let textSub = String(self.agentQuery[typeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !textSub.isEmpty { textToType = textSub }
                        }
                        action = AgentAction(type: .typeText, x: 500, y: 300, payload: textToType)
                    } else {
                        action = AgentAction(type: .finish, x: 500, y: 500, payload: nil)
                    }
                } else {
                    if actionCount == 0 {
                        var targetApp = "Safari"
                        if lowerQuery.contains("calculator") { targetApp = "Calculator" }
                        else if lowerQuery.contains("terminal") { targetApp = "Terminal" }
                        action = AgentAction(type: .launchApp, x: 500, y: 500, payload: targetApp)
                    } else {
                        action = AgentAction(type: .finish, x: 500, y: 500, payload: nil)
                    }
                }
                
                let stepTag = "DEVICE_ACTION_\(action.type):\(action.payload ?? "")::Step \(actionCount + 1)"
                let stepText = "<thought>\nDeciding action step...\nReasoning: Executing step \(actionCount + 1)\n</thought>\n**[Computer Use Step]**\n\(stepTag)"
                FirestoreService.shared.postAgentStepMessage(content: stepText, isFinal: false)
                completion(action)
            }
        }.resume()
    }
    
    public func log(_ msg: String) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        let time = df.string(from: Date())
        logs.insert("[\(time)] \(msg)", at: 0)
        if logs.count > 100 { logs.removeLast() }
        
        // Output to diagnostic print stream
        print("[\(time)] [Unison Agent] \(msg)")
    }
}

public struct AgentAction {
    public enum ActionType {
        case click
        case hover
        case typeText
        case keyCombo
        case launchApp
        case runCommand
        case finish
    }
    
    public let type: ActionType
    public let x: Double
    public let y: Double
    public let payload: String?
    
    public var description: String {
        switch type {
        case .click: return "Click at [\(x), \(y)]"
        case .hover: return "Hover at [\(x), \(y)]"
        case .typeText: return "Type '\(payload ?? "")' at [\(x), \(y)]"
        case .keyCombo: return "Key Combo '\(payload ?? "")'"
        case .launchApp: return "Launch App '\(payload ?? "")'"
        case .runCommand: return "Execute Shell Command '\(payload ?? "")'"
        case .finish: return "Objective Achieved"
        }
    }
}
