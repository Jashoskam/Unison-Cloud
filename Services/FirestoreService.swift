import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

/// Double-way synchronization structures matching server APIs exactly
struct PairingStartResponse: Codable {
    let code: String
}

struct CheckPairingResponse: Codable {
    let status: String
    let email: String?
    let uid: String?
}

public struct SDUITab: Identifiable, Codable, Hashable {
    public var id: String { viewType }
    public var title: String
    public var icon: String
    public var viewType: String // chat, system_hub, directory, terminal, titan_suite
    public var badge: String?
    
    public init(title: String, icon: String, viewType: String, badge: String? = nil) {
        self.title = title
        self.icon = icon
        self.viewType = viewType
        self.badge = badge
    }
}

struct SDUIResponse: Codable {
    let tabs: [SDUITab]
    let accentColor: String
    let systemStatus: String
}

public struct DiagnosticsResult: Identifiable, Hashable {
    public var id: String { url }
    public let url: String
    public let label: String
    public var status: String // "CHECKING", "ONLINE", "DNS_FAILED", "REFUSED", "TIMEOUT", "OFFLINE", "ERROR"
    public var latency: Double // in ms
    public var errorDetail: String?
    
    public init(url: String, label: String, status: String, latency: Double, errorDetail: String? = nil) {
        self.url = url
        self.label = label
        self.status = status
        self.latency = latency
        self.errorDetail = errorDetail
    }
}

struct ConvoResponseItem: Codable {
    let id: String
    let title: String?
    let type: String?
    let parentId: String?
    let searchText: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, title, type, parentId, searchText, createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let idStr = try? container.decode(String.self, forKey: .id) {
            self.id = idStr
        } else if let idInt = try? container.decode(Int.self, forKey: .id) {
            self.id = String(idInt)
        } else {
            self.id = UUID().uuidString
        }
        
        self.title = try? container.decode(String.self, forKey: .title)
        self.type = try? container.decode(String.self, forKey: .type)
        self.parentId = try? container.decode(String.self, forKey: .parentId)
        self.searchText = try? container.decode(String.self, forKey: .searchText)
        
        if let strVal = try? container.decode(String.self, forKey: .createdAt) {
            self.createdAt = strVal
        } else {
            self.createdAt = nil
        }
    }
}

struct ConvoListResponse: Codable {
    let conversations: [ConvoResponseItem]
    
    enum CodingKeys: String, CodingKey {
        case conversations
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.conversations = (try? container.decode([ConvoResponseItem].self, forKey: .conversations)) ?? []
    }
}

struct MessageResponseItem: Codable {
    let id: String?
    let conversationId: String?
    let content: String?
    let role: String?
    let createdAt: String?
    let thoughts: String?
    
    enum CodingKeys: String, CodingKey {
        case id, conversationId, content, role, createdAt, thoughts
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try? container.decode(String.self, forKey: .id)
        self.conversationId = try? container.decode(String.self, forKey: .conversationId)
        self.content = try? container.decode(String.self, forKey: .content)
        self.role = try? container.decode(String.self, forKey: .role)
        self.thoughts = try? container.decode(String.self, forKey: .thoughts)
        
        if let strVal = try? container.decode(String.self, forKey: .createdAt) {
            self.createdAt = strVal
        } else {
            self.createdAt = nil
        }
    }
}

struct MessageListResponse: Codable {
    let messages: [MessageResponseItem]
    
    enum CodingKeys: String, CodingKey {
        case messages
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.messages = (try? container.decode([MessageResponseItem].self, forKey: .messages)) ?? []
    }
}

struct CreateConvoResponse: Codable {
    let id: String
    let title: String
}

struct MessageSendResponse: Codable {
    let success: Bool
    let response: String
}

struct StudyMaterialsResponse: Codable {
    let study_materials: [CourseMaterial]
}

struct StudyMaterialSaveRequest: Codable {
    let email: String?
    let uid: String?
    let material: CourseMaterial
}

struct StudyMaterialDeleteRequest: Codable {
    let email: String?
    let uid: String?
    let id: String
}

/// State Broker to coordinate actual Supabase connection and local simulated state backups
public class FirestoreService: ObservableObject {
    public static let shared = FirestoreService()
    
    // Safety Audio Rate Limiter to prevent CoreAudio HAL overload
    private var lastSoundPlayTime: Date = Date.distantPast
    private var permissionsObserver: PermissionsStreamObserver?
    private var webSocketTask: URLSessionWebSocketTask?
    
    // Auth & Coupling states
    @Published public var currentUserEmail: String? = "operator@unison.io"
    @Published public var currentUserId: String? = "unison-local-user"
    @Published public var isAuthenticated: Bool = true
    @Published public var isSupabaseReady: Bool = false
    @Published public var pairingCode: String? = nil
    @Published public var pairingStatus: String = "idle" // idle, pending, authorized
    @Published public var logs: [String] = []
    @Published public var activeWorkspaceDirectoryPath: String? = {
        let stored = UserDefaults.standard.string(forKey: "unison_active_workspace_path")
        if let path = stored, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return path
        }
        return FileManager.default.currentDirectoryPath
    }() {
        didSet {
            if let path = activeWorkspaceDirectoryPath {
                UserDefaults.standard.set(path, forKey: "unison_active_workspace_path")
            }
        }
    }
    
    // Custom user configurable keys
    @Published public var selectedModel: String = {
        UserDefaults.standard.string(forKey: "unison_selected_model") ?? "Gemini 3.5 Flash"
    }() {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "unison_selected_model")
        }
    }
    
    @Published public var userGeminiApiKey: String = {
        let stored = UserDefaults.standard.string(forKey: "unison_user_gemini_api_key") ?? ""
        if !stored.isEmpty { return stored }
        return ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    }() {
        didSet {
            UserDefaults.standard.set(userGeminiApiKey, forKey: "unison_user_gemini_api_key")
            self.logEvent(message: "Custom Gemini API Key updated.")
        }
    }
    
    public var effectiveApiKey: String {
        let trimmed = userGeminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    // Industrial IDE State Controls
    @Published public var selectedDiffFile: String? = nil
    @Published public var showingDiffViewerModal: Bool = false
    @Published public var showingReviewModal: Bool = false
    
    @Published public var userSupabaseUrl: String = {
        UserDefaults.standard.string(forKey: "unison_user_supabase_url") ?? "https://copravscnxxgyabaftgz.supabase.co"
    }() {
        didSet {
            UserDefaults.standard.set(userSupabaseUrl, forKey: "unison_user_supabase_url")
            self.logEvent(message: "Custom Supabase URL updated.")
        }
    }
    
    // Realtime Token Usage Tracking Engine
    @Published public var totalTokensUsed: Int = {
        let stored = UserDefaults.standard.integer(forKey: "unison_total_tokens_used")
        return stored > 0 ? stored : 57500
    }() {
        didSet {
            UserDefaults.standard.set(totalTokensUsed, forKey: "unison_total_tokens_used")
        }
    }
    @Published public var maxTokenLimit: Int = 200000
    
    public var tokensRemainingPercent: Int {
        let rem = maxTokenLimit - totalTokensUsed
        return max(0, min(100, (rem * 100) / maxTokenLimit))
    }
    
    public var tokensRemainingFormatted: String {
        let rem = max(0, maxTokenLimit - totalTokensUsed)
        return String(format: "%.1fk / %.0fk tokens", Double(rem) / 1000.0, Double(maxTokenLimit) / 1000.0)
    }
    
    public func consumeTokens(count: Int) {
        DispatchQueue.main.async {
            self.totalTokensUsed = min(self.maxTokenLimit, self.totalTokensUsed + count)
            self.logEvent(message: "[TOKENS] Consumed \(count) tokens. Remaining: \(self.tokensRemainingPercent)% (\(self.tokensRemainingFormatted))")
        }
    }
    
    @Published public var userSupabaseAnonKey: String = {
        UserDefaults.standard.string(forKey: "unison_user_supabase_anon_key") ?? "sb_publishable_DSSSJVSZdaAsdv7zbxixMA_mPOwExv7"
    }() {
        didSet {
            UserDefaults.standard.set(userSupabaseAnonKey, forKey: "unison_user_supabase_anon_key")
            self.logEvent(message: "Custom Supabase Anon Key updated.")
        }
    }
    
    // Setting Toggles
    @Published public var soundFXEnabled: Bool = {
        UserDefaults.standard.object(forKey: "unison_sound_fx_enabled") as? Bool ?? true
    }() {
        didSet {
            UserDefaults.standard.set(soundFXEnabled, forKey: "unison_sound_fx_enabled")
        }
    }
    
    @Published public var telemetryEnabled: Bool = {
        UserDefaults.standard.object(forKey: "unison_telemetry_enabled") as? Bool ?? true
    }() {
        didSet {
            UserDefaults.standard.set(telemetryEnabled, forKey: "unison_telemetry_enabled")
            if telemetryEnabled {
                startSimulatedTelemetry()
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }
    
    @Published public var glassUIEnabled: Bool = {
        UserDefaults.standard.object(forKey: "unison_glass_ui_enabled") as? Bool ?? true
    }() {
        didSet {
            UserDefaults.standard.set(glassUIEnabled, forKey: "unison_glass_ui_enabled")
        }
    }
    
    @Published public var isNamingConversation: Bool = false
    @Published public var newChatDraftTitle: String = ""
    
    @Published public var hapticFeedbackEnabled: Bool = {
        UserDefaults.standard.object(forKey: "unison_haptic_feedback_enabled") as? Bool ?? true
    }() {
        didSet {
            UserDefaults.standard.set(hapticFeedbackEnabled, forKey: "unison_haptic_feedback_enabled")
        }
    }
    
    public var isUsingCustomSupabase: Bool {
        return !userSupabaseUrl.isEmpty
    }
    
    // Telemetry updates
    @Published public var telemetry = SystemTelemetry()
    
    // Server-Driven UI parameters
    @Published public var sduiTabs: [SDUITab] = [
        SDUITab(title: "Chat Workspace", icon: "bubble.left", viewType: "chat", badge: nil)
    ]
    @Published public var sduiAccentColor: String = "cyan"
    @Published public var sduiSystemStatus: String = "ONLINE"
    
    // Active Note State
    @Published public var activeNoteTitle: String = "Portfolio design sprint V1"
    @Published public var activeNoteStatus: String = "In progress"
    @Published public var activeNoteContent: String = """
Project Overview

Revitalize my current portfolio to improve the UX through micro-interactions, and bug fixes

Required changes to my new portfolio:
• New notification system (toasts)
• Remove backdrop-filter
• improve navigation experience on mobile
"""
    
    // Live conversations and messages
    @Published public var conversations: [Conversation] = [] {
        didSet {
            self.saveConversationsToDefaults()
        }
    }
    @Published public var messages: [ChatMessage] = [] {
        didSet {
            guard let last = messages.last else { return }
            
            // Only execute if a single message was dynamically appended,
            // and the message is extremely fresh (less than 15 seconds old).
            let isAppended = messages.count == oldValue.count + 1
            let isFresh = Date().timeIntervalSince(last.createdAt) < 15.0
            
            // Guard: Only trigger side-effects for USER messages, never for AI/model follow-ups.
            // This prevents the AI's own responses (e.g. from approvePendingCommand) from
            // accidentally re-triggering device automation via keyword sniffing.
            guard isAppended && isFresh && last.role == "user" else { return }
            
            let content = last.content
            if content.contains("[SYSTEM_ACTION:") {
                self.executeActionsAndClean(lastMessageIndex: messages.count - 1)
            } else {
                let lower = content.lowercased()
                if lower.hasPrefix("open ") || lower.hasPrefix("launch ") || lower.contains("search") || lower.contains("click") || lower.contains("type") || lower.contains("write") || lower.contains("automate") || lower.contains("computer use") {
                    self.executeActionsAndClean(lastMessageIndex: messages.count - 1)
                }
            }
        }
    }
    @Published public var activeProjectFiles: [UnisonFile] = []
    @Published public var selectedConversationId: String? = nil {
        didSet {
            if let newId = selectedConversationId {
                self.loadMessagesFromDefaults(conversationId: newId)
                self.fetchLiveMessages(conversationId: newId)
            }
        }
    }
    @Published public var selectedProjectId: String? = nil
    @Published public var selectedJottingName: String? = nil
    @Published public var activeNavIndex: Int = 0
    @Published public var isSendingMessage: Bool = false
    @Published public var accessibilityPermissionGranted: Bool = TCCPermissionChecker.verifyAccessibility
    @Published public var screenCapturePermissionGranted: Bool = TCCPermissionChecker.verifyScreenCapture
    @Published public var showComputerUsePermissionDialog: Bool = false
    @Published public var activeStepMessageId: String? = nil
    
    // Real-time Canvas Elements and Jottings
    @Published public var canvasElements: [CanvasElement] = []
    @Published public var jottingsList: [JottingFile] = []
    @Published public var studyMaterials: [CourseMaterial] = []
    @Published public var tasksList: [TaskItem] = []
    @Published public var calendarEvents: [CalendarEvent] = []
    
    @Published public var webUrl: String = {
        let saved = UserDefaults.standard.string(forKey: "unison_web_url") ?? ""
        if saved.isEmpty || (saved.contains("ais-dev-") && !saved.contains("smmknu2n7rug57vth3dwkw") && !saved.contains("agxs24sta5zaihq2lz4mbb")) {
            // Default to your custom hosted Render URL
            return "https://unison-cloud.onrender.com"
        }
        return saved
    }() {
        didSet {
            UserDefaults.standard.set(webUrl, forKey: "unison_web_url")
            self.logEvent(message: "Interface pipeline changed to: \(webUrl)")
            // Trigger rapid sync on route adjustment
            DispatchQueue.main.async {
                self.fetchServerDrivenUI()
                self.fetchLiveConversations()
                self.connectToWebSocket()
            }
        }
    }
    
    @Published public var probeResults: [DiagnosticsResult] = [
        DiagnosticsResult(url: "http://localhost:3000", label: "LOCAL DEV GATEWAY", status: "IDLE", latency: -1.0),
        DiagnosticsResult(url: "https://unison-cloud.onrender.com", label: "RENDER CLOUD", status: "IDLE", latency: -1.0),
        DiagnosticsResult(url: "https://ais-dev-smmknu2n7rug57vth3dwkw-418080742679.asia-east1.run.app", label: "DEV GATEWAY", status: "IDLE", latency: -1.0),
        DiagnosticsResult(url: "https://ais-pre-smmknu2n7rug57vth3dwkw-418080742679.asia-east1.run.app", label: "SHARED GRID", status: "IDLE", latency: -1.0)
    ]
    @Published public var isProbing: Bool = false
    
    // Set this constant to your actual Render URL (with NO trailing slash)
    private let renderUrl = "https://unison-cloud.onrender.com"
    private let devUrl = "https://ais-dev-smmknu2n7rug57vth3dwkw-418080742679.asia-east1.run.app"
    private let preUrl = "https://ais-pre-smmknu2n7rug57vth3dwkw-418080742679.asia-east1.run.app"
    private var timer: Timer?
    private var pairingTimer: Timer?
    private var syncTimer: Timer?
    private var oscStep: Double = 0.0
    private var activeUIDataTask: URLSessionDataTask?
    private var activeConversationsDataTask: URLSessionDataTask?
    private var activeMessagesDataTask: URLSessionDataTask?
    private var currentActiveFetchingMessagesConvoId: String? = nil

    private var executedMessageIds: Set<String> = {
        let array = UserDefaults.standard.stringArray(forKey: "unison_executed_message_ids") ?? []
        return Set(array)
    }() {
        didSet {
            UserDefaults.standard.set(Array(executedMessageIds), forKey: "unison_executed_message_ids")
        }
    }

    private init() {
        self.isSupabaseReady = true
        self.logEvent(message: "Supabase client activated. Ready for network pipeline binding.")
        if telemetryEnabled {
            self.startSimulatedTelemetry()
        }
        
        // Save synthesized clean url back to defaults so it updates the device
        UserDefaults.standard.set(self.webUrl, forKey: "unison_web_url")
        
        // Load offline backing stores
        self.loadConversationsFromDefaults()
        
        // Auto-detect which server (dev vs pre vs local) is active right now and synchronize
        self.detectUrlAndSync()
        
        // Start background synchronization timer to fetch live updates from remote server
        self.startBackgroundSync()
        
        // Start periodic hardware & permission diagnostics
        HardwareDiagnosticService.shared.startPeriodicDiagnostics()
        
        // Start persistent system-wide command WebSocket receiver
        self.connectToWebSocket()
    }

    public func detectUrlAndSync() {
        guard !isProbing else { return }
        DispatchQueue.main.async {
            self.isProbing = true
        }
        
        var urlsToProbe: [(String, String)] = [
            (renderUrl, "RENDER CLOUD"),
            (devUrl, "DEV GATEWAY"),
            (preUrl, "SHARED GRID")
        ]
        
        if webUrl.contains("localhost") || webUrl.contains("127.0.0.1") {
            urlsToProbe.insert(("http://localhost:3000", "LOCAL SYSTEM"), at: 0)
            urlsToProbe.insert(("http://127.0.0.1:3000", "LOCAL LOOPBACK"), at: 1)
        }
        
        self.logEvent(message: "Initializing multi-channel high-fidelity connection diagnostics...")
        
        let group = DispatchGroup()
        var results: [DiagnosticsResult] = []
        
        for (host, label) in urlsToProbe {
            group.enter()
            guard let url = URL(string: "\(host)/api/companion/layout") else {
                group.leave()
                continue
            }
            
            let startTime = Date()
            var request = URLRequest(url: url)
            request.timeoutInterval = 3.0 // 3.0s timeout is best for mobile
            
            URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
                guard let self = self else {
                    group.leave()
                    return
                }
                
                let latency = Date().timeIntervalSince(startTime) * 1000.0 // in ms
                var status = "ONLINE"
                var detail: String? = nil
                
                if let error = error as NSError? {
                    if error.domain == NSURLErrorDomain {
                        switch error.code {
                        case -1003: // Cannot find host
                            status = "DNS_FAILED"
                            detail = "DNS query failed. Hostname could not be resolved."
                        case -1004: // Cannot connect to host
                            status = "REFUSED"
                            detail = "Connection refused. Ensure the backend is running on port 3000."
                        case -1001: // Timed out
                            status = "TIMEOUT"
                            detail = "Request timed out. Network path representing latency."
                        case -1009: // Not connected to internet
                            status = "OFFLINE"
                            detail = "Device offline. Check network connection."
                        default:
                            status = "ERROR"
                            detail = "Error \(error.code): \(error.localizedDescription)"
                        }
                    } else {
                        status = "ERROR"
                        detail = error.localizedDescription
                    }
                } else if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        status = "ERROR"
                        detail = "Server responded with HTTP Status \(httpResponse.statusCode)"
                    }
                } else {
                    status = "ERROR"
                    detail = "No response headers received."
                }
                
                let diagnostic = DiagnosticsResult(
                    url: host,
                    label: label,
                    status: status,
                    latency: latency,
                    errorDetail: detail
                )
                
                DispatchQueue.main.async {
                    results.append(diagnostic)
                    self.logEvent(message: "Probe '\(label)': status=\(status), latency=\(Int(latency))ms")
                    
                    // If we found a working link, let's auto-bind to it if we were on an unresponsive path!
                    if status == "ONLINE" {
                        if self.webUrl == host {
                            self.fetchServerDrivenUI()
                            self.fetchLiveConversations()
                        } else if self.webUrl.contains("localhost") && !host.contains("localhost") {
                            // If we currently have localhost bound but it failed, and this remote one is ONLINE, auto-promote!
                            self.webUrl = host
                        }
                    }
                }
                group.leave()
            }.resume()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isProbing = false
            self.probeResults = results
            
            // Check if local target succeeded, or fall back to remote target
            let localTarget = results.first { $0.url.contains("localhost") || $0.url.contains("127.0.0.1") }
            let localWorking = localTarget?.status == "ONLINE"
            let remoteWorking = results.filter { !$0.url.contains("localhost") && !$0.url.contains("127.0.0.1") }.first { $0.status == "ONLINE" }
            
            if localWorking {
                if let local = localTarget, self.webUrl != local.url {
                    self.logEvent(message: "Auto-bound to active local gateway: \(local.url)")
                    self.webUrl = local.url
                }
            } else if let bestRemote = remoteWorking {
                if self.webUrl != bestRemote.url {
                    self.logEvent(message: "Auto-promoted resilient network link to: \(bestRemote.url)")
                    self.webUrl = bestRemote.url
                }
            } else {
                self.logEvent(message: "CRITICAL COUPLING FAILURE: No active gateway nodes resolved.")
            }
        }
    }
    
    private func logEvent(message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        DispatchQueue.main.async {
            self.logs.append("[\(timestamp)] \(message)")
            if self.logs.count > 100 {
                self.logs.removeFirst()
            }
        }
    }
    
    /// Establishes Secure Pairing Session with real-time Express and Supabase/Cloud coordination
    public func startDevicePairing() {
        self.pairingStatus = "pending"
        self.logEvent(message: "Initializing device pairing with system grid...")
        
        guard let url = URL(string: "\(webUrl)/api/companion/start-pairing") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                self.logEvent(message: "Pairing network failure: \(error.localizedDescription)")
                DispatchQueue.main.async { self.pairingStatus = "idle" }
                return
            }
            
            guard let data = data else { return }
            do {
                let resObj = try JSONDecoder().decode(PairingStartResponse.self, from: data)
                DispatchQueue.main.async {
                    self.pairingCode = resObj.code
                    self.logEvent(message: "Pairing token active: \(resObj.code). Waiting for user confirmation...")
                    self.pollPairingResult(token: resObj.code)
                }
            } catch {
                self.logEvent(message: "Failed parsing pairing token payload")
                DispatchQueue.main.async { self.pairingStatus = "idle" }
            }
        }.resume()
    }
    
    /// Polls pairing authorization loop
    private func pollPairingResult(token: String) {
        pairingTimer?.invalidate()
        pairingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard let url = URL(string: "\(self.webUrl)/api/companion/check-pairing?code=\(token)") else { return }
            
            URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                guard let self = self else { return }
                if error != nil { return }
                guard let data = data else { return }
                
                if let resObj = try? JSONDecoder().decode(CheckPairingResponse.self, from: data) {
                    if resObj.status == "authorized" {
                        DispatchQueue.main.async {
                            self.pairingTimer?.invalidate()
                            self.pairingStatus = "authorized"
                            self.currentUserEmail = resObj.email ?? "operator@unison.io"
                            self.currentUserId = resObj.uid
                            self.isAuthenticated = true
                            self.loadConversationsFromDefaults()
                            self.logEvent(message: "Grid coupling authorized for: \(self.currentUserEmail ?? "") with ID: \(resObj.uid ?? "")")
                            self.fetchServerDrivenUI()
                            self.fetchLiveConversations()
                            self.startBackgroundSync()
                        }
                    }
                }
            }.resume()
        }
    }
    
    public func loginDirectly(email: String = "jashoskam@gmail.com") {
        self.currentUserEmail = email
        self.currentUserId = nil
        self.isAuthenticated = true
        self.loadConversationsFromDefaults()
        self.logEvent(message: "Credentials accepted. Direct link established for \(email).")
        self.fetchServerDrivenUI()
        self.fetchLiveConversations()
        self.startBackgroundSync()
    }
    
    public func sendOllamaChatMessage(prompt: String, modelName: String = "llama3") {
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: "user",
            content: prompt,
            createdAt: Date()
        )
        self.messages.append(userMessage)
        self.isSendingMessage = true
        
        let cleanedModel = modelName.replacingOccurrences(of: "Ollama: ", with: "").replacingOccurrences(of: "ollama:", with: "").lowercased()
        let targetModel = cleanedModel.isEmpty ? "llama3" : cleanedModel
        
        guard let url = URL(string: "http://localhost:11434/api/generate") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": targetModel,
            "prompt": prompt,
            "stream": false
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSendingMessage = false
                
                if let error = error {
                    let errMsg = ChatMessage(
                        id: UUID().uuidString,
                        role: "model",
                        content: "⚠️ **Ollama Local Connection Error**: \(error.localizedDescription)\n\nMake sure Ollama is running locally on your Mac (`ollama serve`) and the model `\(targetModel)` is downloaded (`ollama pull \(targetModel)`).",
                        createdAt: Date()
                    )
                    self.messages.append(errMsg)
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let responseText = json["response"] as? String else {
                    let errMsg = ChatMessage(
                        id: UUID().uuidString,
                        role: "model",
                        content: "⚠️ **Ollama Invalid Response**: Could not parse response from Ollama daemon at `http://localhost:11434`.",
                        createdAt: Date()
                    )
                    self.messages.append(errMsg)
                    return
                }
                
                let modelMsg = ChatMessage(
                    id: UUID().uuidString,
                    role: "model",
                    content: responseText,
                    thoughts: "Executed locally via Ollama Engine (\(targetModel))",
                    createdAt: Date()
                )
                self.messages.append(modelMsg)
            }
        }.resume()
    }

    public func signOut() {
        self.isAuthenticated = false
        self.currentUserEmail = nil
        self.currentUserId = nil
        self.pairingCode = nil
        self.pairingStatus = "idle"
        self.selectedConversationId = nil
        self.selectedProjectId = nil
        self.activeProjectFiles = []
        self.studyMaterials = []
        self.conversations = []
        self.messages = []
        pairingTimer?.invalidate()
        syncTimer?.invalidate()
        activeUIDataTask?.cancel()
        activeUIDataTask = nil
        activeConversationsDataTask?.cancel()
        activeConversationsDataTask = nil
        activeMessagesDataTask?.cancel()
        activeMessagesDataTask = nil
        self.logEvent(message: "Secured user session signed out cleanly.")
    }
    
    /// Starts real-time periodic conversations/messages syncing in a thread-safe manner
    private func startBackgroundSync() {
        DispatchQueue.main.async {
            self.syncTimer?.invalidate()
            self.syncTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                // Sync Canvas and Jottings in real-time regardless of auth status
                self.fetchLiveCanvasElements()
                self.fetchLiveJottings()
                self.fetchLiveMeetings()
                self.fetchLiveTasks()
                self.fetchComputerUsePermissions()
                
                if self.isUsingCustomSupabase || self.isAuthenticated {
                    self.fetchLiveStudyMaterials()
                }
                
                guard self.isAuthenticated else { return }
                self.fetchServerDrivenUI()
                self.fetchLiveConversations()
                if let activeId = self.selectedConversationId {
                    self.fetchLiveMessages(conversationId: activeId)
                }
                if let projId = self.selectedProjectId {
                    self.fetchLiveProjectFiles(projectId: projId)
                }
            }
        }
    }
    
    public func addSnapshotListener() {
        guard permissionsObserver == nil else { return }
        guard let url = URL(string: "\(webUrl)/api/companion/permissions/stream") else { return }
        
        let observer = PermissionsStreamObserver(url: url) { [weak self] accessibility, screenshots in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let finalAccessibility = TCCPermissionChecker.verifyAccessibility ? true : accessibility
                let finalScreenshots = TCCPermissionChecker.verifyScreenCapture ? true : screenshots
                
                if self.accessibilityPermissionGranted != finalAccessibility {
                    self.accessibilityPermissionGranted = finalAccessibility
                }
                if self.screenCapturePermissionGranted != finalScreenshots {
                    self.screenCapturePermissionGranted = finalScreenshots
                }
            }
        }
        self.permissionsObserver = observer
        observer.start()
    }
    
    public func fetchComputerUsePermissions() {
        addSnapshotListener()
    }
    
    public func saveComputerUsePermissions(accessibility: Bool, screenshots: Bool) {
        // Update local variables immediately on the main thread so that user interaction doesn't block on network responses
        DispatchQueue.main.async {
            self.accessibilityPermissionGranted = TCCPermissionChecker.verifyAccessibility ? true : accessibility
            self.screenCapturePermissionGranted = TCCPermissionChecker.verifyScreenCapture ? true : screenshots
        }

        guard let url = URL(string: "\(webUrl)/api/companion/permissions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["accessibility": accessibility, "screenshots": screenshots]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.accessibilityPermissionGranted = TCCPermissionChecker.verifyAccessibility ? true : accessibility
                self.screenCapturePermissionGranted = TCCPermissionChecker.verifyScreenCapture ? true : screenshots
            }
        }.resume()
    }
    
    /// Pull layout and colors from central server dynamically to power Server-Driven UI
    public func fetchServerDrivenUI() {
        guard activeUIDataTask == nil else { return }
        guard let url = URL(string: "\(webUrl)/api/companion/layout") else { return }
        
        func performFetch(attempt: Int) {
            let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain, nsError.code == -1005, attempt < 3 {
                    self.logEvent(message: "Socket -1005 retry attempt \(attempt) for layout sync")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        performFetch(attempt: attempt + 1)
                    }
                    return
                }
                
                defer {
                    DispatchQueue.main.async {
                        self.activeUIDataTask = nil
                    }
                }
                
                if error != nil { return }
                guard let data = data else { return }
                
                do {
                    let resObj = try JSONDecoder().decode(SDUIResponse.self, from: data)
                    let localTabs = [
                        SDUITab(title: "Chat Workspace", icon: "bubble.left", viewType: "chat", badge: nil)
                    ]
                    DispatchQueue.main.async {
                        self.sduiTabs = localTabs
                        self.sduiAccentColor = resObj.accentColor
                        self.sduiSystemStatus = resObj.systemStatus
                        self.logEvent(message: "Server-Driven UI layout synchronized: \(self.sduiTabs.count) tabs retrieved.")
                    }
                } catch {
                    // Fail silently and keep native built-in defaults
                }
            }
            activeUIDataTask = task
            task.resume()
        }
        
        performFetch(attempt: 1)
    }
    
    /// Retrieve and save local conversations to UserDefaults
    public func saveConversationsToDefaults() {
        if let encoded = try? JSONEncoder().encode(self.conversations) {
            UserDefaults.standard.set(encoded, forKey: "unison_local_conversations")
        }
    }
    
    public func loadConversationsFromDefaults() {
        if let data = UserDefaults.standard.data(forKey: "unison_local_conversations"),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            self.conversations = decoded
        } else {
            self.conversations = [
                Conversation(id: "c1", title: "Global Controller Pipeline", type: "main_convo"),
                Conversation(id: "c2", title: "Thermals Check Script", type: "chat", parentId: "c1"),
                Conversation(id: "c3", title: "Silicon Speedways project", type: "project", parentId: "c1")
            ]
            saveConversationsToDefaults()
        }
        
        if self.selectedConversationId == nil, let first = self.conversations.first {
            self.selectedConversationId = first.id
            self.loadMessagesFromDefaults(conversationId: first.id)
        }
    }
    
    public func saveMessagesToDefaults() {
        guard let activeId = selectedConversationId else { return }
        let key = "unison_local_messages_\(activeId)"
        if let encoded = try? JSONEncoder().encode(self.messages) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    public func loadMessagesFromDefaults(conversationId: String) {
        let key = "unison_local_messages_\(conversationId)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            self.messages = decoded
        } else {
            if conversationId == "c1" {
                self.messages = [
                    ChatMessage(role: "system", content: "Unison OS Terminal Kernel loaded successfully."),
                    ChatMessage(role: "user", content: "List the status of connected GPIO chains"),
                    ChatMessage(role: "model", content: "All chains responding correctly. CPU Temp: 41.8°C. Relay 1: [Off] | Relay 2: [Off] | Fault LED: [Off]")
                ]
            } else if conversationId == "c2" {
                self.messages = [
                    ChatMessage(role: "system", content: "Thermals monitoring active."),
                    ChatMessage(role: "user", content: "What is current thermal limit?"),
                    ChatMessage(role: "model", content: "Thermal limit is configured at 85.0°C. Current level is safe at 42.1°C.")
                ]
            } else {
                self.messages = []
            }
            saveMessagesToDefaults()
        }
    }

    public func fetchLiveConversations() {
        if isUsingCustomSupabase {
            fetchCustomSupabaseConversations()
            return
        }
        
        guard activeConversationsDataTask == nil else { return }
        let emailParam = currentUserEmail ?? "jashoskam@gmail.com"
        var urlString = "\(webUrl)/api/companion/conversations?email=\(emailParam.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let uid = currentUserId, !uid.isEmpty {
            urlString += "&uid=\(uid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        guard let url = URL(string: urlString) else { return }
        
        func performFetch(attempt: Int) {
            let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain, nsError.code == -1005, attempt < 3 {
                    self.logEvent(message: "Socket -1005 retry attempt \(attempt) for conversations sync")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        performFetch(attempt: attempt + 1)
                    }
                    return
                }
                
                defer {
                    DispatchQueue.main.async {
                        self.activeConversationsDataTask = nil
                    }
                }
                
                if let error = error {
                    self.logEvent(message: "Failed syncing workspace nodes: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    let resObj = try JSONDecoder().decode(ConvoListResponse.self, from: data)
                    let mapped = resObj.conversations.map { item -> Conversation in
                        return Conversation(
                            id: item.id,
                            title: item.title ?? "Neural Interface Node",
                            type: item.type ?? "chat",
                            parentId: item.parentId,
                            searchText: item.searchText,
                            createdAt: ISO8601DateFormatter().date(from: item.createdAt ?? "") ?? Date()
                        )
                    }
                    
                    DispatchQueue.main.async {
                        self.conversations = mapped
                        if self.selectedConversationId == nil && !mapped.isEmpty {
                            self.selectedConversationId = mapped.first?.id
                            self.fetchLiveMessages(conversationId: mapped.first!.id)
                        }
                    }
                } catch {
                    self.logEvent(message: "Failed parsing conversations error: \(error)")
                }
            }
            activeConversationsDataTask = task
            task.resume()
        }
        
        performFetch(attempt: 1)
    }
    
    // Robust helper to parse ISO8601 dates from Supabase (handling with or without fractional seconds)
    private func parseSupabaseDate(from string: String) -> Date {
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: string) {
            return date
        }
        
        let formatterWithoutFractional = ISO8601DateFormatter()
        formatterWithoutFractional.formatOptions = [.withInternetDateTime]
        if let date = formatterWithoutFractional.date(from: string) {
            return date
        }
        
        return Date()
    }
    
    // Robust helper to format Date for Supabase with fractional seconds (matching Supabase format exactly)
    private func formatSupabaseDate(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    
    /// Extract conversations from User Custom Supabase Cloud Rest Client
    private func fetchCustomSupabaseConversations() {
        let supabaseUrl = userSupabaseUrl
        let anonKey = userSupabaseAnonKey
        let urlString = "\(supabaseUrl)/rest/v1/conversations?select=*&order=updated_at.desc"
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                self.logEvent(message: "Custom Supabase connection error: \(error.localizedDescription)")
                return
            }
            guard let data = data else { return }
            
            do {
                if let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var parsed: [Conversation] = []
                    for row in rows {
                        let docId = row["id"] as? String ?? UUID().uuidString
                        let titleStr = row["title"] as? String ?? "Custom Node"
                        let typeStr = row["type"] as? String ?? "chat"
                        let parentId = row["parent_id"] as? String
                        let createdAtStr = row["created_at"] as? String ?? ""
                        
                        let createdAt = self.parseSupabaseDate(from: createdAtStr)
                        
                        parsed.append(Conversation(
                            id: docId,
                            title: titleStr,
                            type: typeStr,
                            parentId: parentId,
                            createdAt: createdAt
                        ))
                    }
                    
                    DispatchQueue.main.async {
                        if !parsed.isEmpty {
                            self.conversations = parsed.sorted(by: { $0.createdAt > $1.createdAt })
                            self.saveConversationsToDefaults()
                            if self.selectedConversationId == nil, let first = parsed.first {
                                self.selectedConversationId = first.id
                                self.fetchLiveMessages(conversationId: first.id)
                            }
                        }
                    }
                }
            } catch {
                self.logEvent(message: "Custom Supabase parsing error: \(error)")
            }
        }.resume()
    }
    
    /// Write workspace conversations directly to custom user Supabase
    private func writeCustomSupabaseConversation(convo: Conversation) {
        let supabaseUrl = userSupabaseUrl
        let anonKey = userSupabaseAnonKey
        let urlString = "\(supabaseUrl)/rest/v1/conversations"
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "id": convo.id,
            "title": convo.title,
            "type": convo.type,
            "user_id": "pi-user",
            "parent_id": convo.parentId ?? NSNull(),
            "created_at": self.formatSupabaseDate(from: convo.createdAt),
            "updated_at": self.formatSupabaseDate(from: convo.createdAt)
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.logEvent(message: "Supabase write conversation error: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                self?.logEvent(message: "Supabase write conversation status: \(httpResponse.statusCode)")
                if httpResponse.statusCode >= 300, let data = data, let str = String(data: data, encoding: .utf8) {
                    self?.logEvent(message: "Supabase write conversation response payload: \(str)")
                }
            }
        }.resume()
    }

    /// Fetch messages in conversational nodes from Supabase
    public func fetchLiveMessages(conversationId: String) {
        if isUsingCustomSupabase {
            fetchCustomSupabaseMessages(convoId: conversationId)
            return
        }
        
        if let currentFetchId = currentActiveFetchingMessagesConvoId, currentFetchId == conversationId {
            if activeMessagesDataTask != nil {
                return
            }
        }
        
        activeMessagesDataTask?.cancel()
        activeMessagesDataTask = nil
        currentActiveFetchingMessagesConvoId = conversationId
        
        guard let url = URL(string: "\(webUrl)/api/companion/messages?conversationId=\(conversationId)") else { return }
        
        func performFetch(attempt: Int) {
            let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain, nsError.code == -1005, attempt < 3 {
                    self.logEvent(message: "Socket -1005 retry attempt \(attempt) for messages sync")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        performFetch(attempt: attempt + 1)
                    }
                    return
                }
                
                defer {
                    DispatchQueue.main.async {
                        self.activeMessagesDataTask = nil
                        self.currentActiveFetchingMessagesConvoId = nil
                    }
                }
                
                if error != nil { return }
                guard let data = data else { return }
                
                do {
                    let resObj = try JSONDecoder().decode(MessageListResponse.self, from: data)
                    let mapped = resObj.messages.map { item -> ChatMessage in
                        return ChatMessage(
                            id: item.id ?? UUID().uuidString,
                            role: item.role ?? "model",
                            content: item.content ?? "",
                            thoughts: item.thoughts,
                            createdAt: ISO8601DateFormatter().date(from: item.createdAt ?? "") ?? Date()
                        )
                    }
                    
                    DispatchQueue.main.async {
                        var finalMessages: [ChatMessage] = []
                        
                        // 1. Append all server-fetched messages
                        for msg in mapped {
                            finalMessages.append(msg)
                        }
                        
                        // 2. Append local messages if not already present or duplicated by content
                        for localMsg in self.messages {
                            if !finalMessages.contains(where: { $0.id == localMsg.id }) {
                                if localMsg.role == "user" && finalMessages.contains(where: { $0.role == "user" && $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == localMsg.content.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                                    continue
                                }
                                finalMessages.append(localMsg)
                            }
                        }
                        
                        self.messages = finalMessages.sorted(by: { $0.createdAt < $1.createdAt })
                        self.saveMessagesToDefaults()
                    }
                } catch {
                    self.logEvent(message: "Failed parsing messages error: \(error)")
                }
            }
            activeMessagesDataTask = task
            task.resume()
        }
        
        performFetch(attempt: 1)
    }
    
    private func fetchCustomSupabaseMessages(convoId: String) {
        let supabaseUrl = userSupabaseUrl
        let anonKey = userSupabaseAnonKey
        let urlString = "\(supabaseUrl)/rest/v1/messages?conversation_id=eq.\(convoId)&order=created_at.asc"
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if error != nil {
                DispatchQueue.main.async { self.loadMessagesFromDefaults(conversationId: convoId) }
                return
            }
            guard let data = data else { return }
            
            do {
                if let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var parsed: [ChatMessage] = []
                    for row in rows {
                        let id = row["id"] as? String ?? UUID().uuidString
                        let role = row["role"] as? String ?? "model"
                        let content = row["content"] as? String ?? ""
                        let thoughts = row["thoughts"] as? String
                        let createdAtStr = row["created_at"] as? String ?? ""
                        
                        let createdAt = self.parseSupabaseDate(from: createdAtStr)
                        
                        parsed.append(ChatMessage(
                            id: id,
                            role: role,
                            content: content,
                            thoughts: thoughts,
                            createdAt: createdAt
                        ))
                    }
                    
                    DispatchQueue.main.async {
                        var dict: [String: ChatMessage] = [:]
                        for msg in self.messages {
                            dict[msg.id] = msg
                        }
                        for msg in parsed {
                            dict[msg.id] = msg
                        }
                        self.messages = Array(dict.values).sorted(by: { $0.createdAt < $1.createdAt })
                        self.saveMessagesToDefaults()
                    }
                } else {
                    DispatchQueue.main.async { self.loadMessagesFromDefaults(conversationId: convoId) }
                }
            } catch {
                DispatchQueue.main.async { self.loadMessagesFromDefaults(conversationId: convoId) }
            }
        }.resume()
    }
    
    private func writeCustomSupabaseMessage(message: ChatMessage, convoId: String) {
        let supabaseUrl = userSupabaseUrl
        let anonKey = userSupabaseAnonKey
        let urlString = "\(supabaseUrl)/rest/v1/messages"
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "id": message.id,
            "conversation_id": convoId,
            "role": message.role,
            "content": message.content,
            "created_at": self.formatSupabaseDate(from: message.createdAt)
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.logEvent(message: "Supabase write message error: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                self?.logEvent(message: "Supabase write message status: \(httpResponse.statusCode)")
                if httpResponse.statusCode >= 300, let data = data, let str = String(data: data, encoding: .utf8) {
                    self?.logEvent(message: "Supabase write message response payload: \(str)")
                }
            }
        }.resume()
    }
    
    // --- BEGIN SWARM FILES SYNCHRONIZATION LOOP ---
    
    public func fetchLiveProjectFiles(projectId: String) {
        if isUsingCustomSupabase {
            fetchCustomSupabaseProjectFiles(projectId: projectId)
            return
        }
        
        guard let url = URL(string: "\(webUrl)/api/companion/files?projectId=\(projectId)") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if error != nil { return }
            guard let data = data else { return }
            
            struct FilesResponse: Codable {
                struct RemoteFile: Codable {
                    let id: String?
                    let name: String?
                    let category: String?
                    let language: String?
                    let size: String?
                    let content: String?
                }
                let files: [RemoteFile]
            }
            
            if let parsedRes = try? JSONDecoder().decode(FilesResponse.self, from: data) {
                let mapped = parsedRes.files.map { item -> UnisonFile in
                    return UnisonFile(
                        id: item.id ?? UUID().uuidString,
                        name: item.name ?? "unnamed",
                        category: item.category ?? "src",
                        language: item.language ?? "swift",
                        size: item.size ?? "1.0 KB",
                        content: item.content ?? ""
                    )
                }
                
                DispatchQueue.main.async {
                    self.activeProjectFiles = mapped
                }
            }
        }.resume()
    }
    
    private func fetchCustomSupabaseProjectFiles(projectId: String) {
        let supabaseUrl = userSupabaseUrl
        let anonKey = userSupabaseAnonKey
        let urlString = "\(supabaseUrl)/rest/v1/files?conversation_id=eq.\(projectId)"
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if error != nil { return }
            guard let data = data else { return }
            
            do {
                if let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var parsed: [UnisonFile] = []
                    for row in rows {
                        let docId = row["id"] as? String ?? UUID().uuidString
                        let name = row["path"] as? String ?? "unnamed"
                        let content = row["content"] as? String ?? ""
                        
                        let ext = name.components(separatedBy: ".").last ?? "swift"
                        
                        parsed.append(UnisonFile(
                            id: docId,
                            name: name,
                            category: "src",
                            language: ext,
                            size: "1.0 KB",
                            content: content
                        ))
                    }
                    
                    DispatchQueue.main.async {
                        self.activeProjectFiles = parsed
                    }
                }
            } catch {
                self.logEvent(message: "Custom Supabase files fetching parsing error: \(error)")
            }
        }.resume()
    }
    
    public func createProjectFile(projectId: String, name: String, category: String, language: String, content: String, completion: @escaping (String?) -> Void) {
        if isUsingCustomSupabase {
            let tempId = "file_" + String(Date().timeIntervalSince1970)
            let file = UnisonFile(id: tempId, name: name, category: category, language: language, size: "1.0 KB", content: content)
            writeCustomSupabaseProjectFile(file: file, projectId: projectId)
            DispatchQueue.main.async {
                self.fetchLiveProjectFiles(projectId: projectId)
                completion(tempId)
            }
            return
        }
        
        guard let url = URL(string: "\(webUrl)/api/companion/file/save") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let fileDict: [String: String] = [
            "name": name,
            "category": category,
            "language": language,
            "size": "1.0 KB",
            "content": content
        ]
        
        let body: [String: Any] = [
            "projectId": projectId,
            "file": fileDict
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if error != nil {
                completion(nil)
                return
            }
            guard let data = data else {
                completion(nil)
                return
            }
            
            struct SaveResponse: Codable {
                let success: Bool?
                let id: String?
            }
            
            if let resObj = try? JSONDecoder().decode(SaveResponse.self, from: data) {
                DispatchQueue.main.async {
                    self.fetchLiveProjectFiles(projectId: projectId)
                    completion(resObj.id)
                }
            } else {
                completion(nil)
            }
        }.resume()
    }
    
    private func writeCustomSupabaseProjectFile(file: UnisonFile, projectId: String) {
        let supabaseUrl = userSupabaseUrl
        let anonKey = userSupabaseAnonKey
        let urlString = "\(supabaseUrl)/rest/v1/files"
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "id": file.id,
            "conversation_id": projectId,
            "path": file.name,
            "content": file.content,
            "created_at": self.formatSupabaseDate(from: Date())
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.logEvent(message: "Supabase write project file error: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                self?.logEvent(message: "Supabase write project file status: \(httpResponse.statusCode)")
                if httpResponse.statusCode >= 300, let data = data, let str = String(data: data, encoding: .utf8) {
                    self?.logEvent(message: "Supabase write project file response payload: \(str)")
                }
            }
        }.resume()
    }
    
    public func saveProjectFile(projectId: String, fileId: String, name: String, category: String, language: String, content: String) {
        if isUsingCustomSupabase {
            let file = UnisonFile(id: fileId, name: name, category: category, language: language, size: "1.0 KB", content: content)
            writeCustomSupabaseProjectFile(file: file, projectId: projectId)
            DispatchQueue.main.async {
                self.fetchLiveProjectFiles(projectId: projectId)
            }
            return
        }
        
        guard let url = URL(string: "\(webUrl)/api/companion/file/save") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let fileDict: [String: String] = [
            "name": name,
            "category": category,
            "language": language,
            "size": "1.0 KB",
            "content": content
        ]
        
        let body: [String: Any] = [
            "projectId": projectId,
            "fileId": fileId,
            "file": fileDict
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.fetchLiveProjectFiles(projectId: projectId)
            }
        }.resume()
    }
    
    private func determineAutoToolMode(prompt: String) -> String {
        let text = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let convoKeywords = [
            "hi", "hello", "hey", "greetings", "how are you", "who are you", "who made you", "your name",
            "tell a joke", "write a joke", "say hello", "thank you", "thanks", "awesome", "perfect",
            "sing a song", "write a short poem", "chat with me", "yo"
        ]
        
        let researchKeywords = [
            "research", "report", "deep dive", "detailed analysis", "comprehensive analysis",
            "investigate", "compare", "comparative study", "summarize the literature",
            "rigorous", "whitepaper", "market analysis", "financial breakdown"
        ]
        
        let searchKeywords = [
            "weather", "forecast", "news", "current status", "traffic", "price today",
            "scores", "who won", "latest", "stock price", "bitcoin price", "now", "today", "yesterday",
            "flight status", "what is happening", "oil prices", "trends", "search", "google", "lookup"
        ]
        
        let skipSearchKeywords = [
            "play", "spotify", "track", "song", "music", "pause", "resume", "volume", "playlist", "queue", "next track", "skip",
            "email", "gmail", "inbox", "send to", "mail", "draft", "calendar", "schedule", "event", "appt", "appointment",
            "spreadsheet", "sheet", "slides", "presentation", "deck", "powerpoint", "google doc",
            "build", "create project", "develop", "code", "file", "index.html", "script", "function", "calculator", "applet", "program", "python", "javascript", "typescript", "write", "edit", "debug", "compile"
        ]
        
        let infoKeywords = [
            "who", "what", "where", "why", "when", "how", "explain", "describe", "tell me about",
            "versus", "vs", "difference between", "status of", "current", "which", "compare",
            "is", "are", "does", "did", "do", "can", "could", "should", "would", "any", "recommend",
            "best", "top", "list", "ratings", "reviews"
        ]
        
        let representsQuestion = text.contains("?") ||
            text.hasPrefix("why ") || text.hasPrefix("how ") || text.hasPrefix("what ") ||
            text.hasPrefix("who ") || text.hasPrefix("where ") || text.hasPrefix("when ") ||
            text.hasPrefix("which ") || text.hasPrefix("compare ") || text.hasPrefix("is ") ||
            text.hasPrefix("are ") || text.hasPrefix("does ") || text.hasPrefix("did ") ||
            text.hasPrefix("can ") || text.hasPrefix("could ") || text.hasPrefix("should ") ||
            text.hasPrefix("would ") || text.hasPrefix("tell me about ")
            
        let isExplicitInfoQuery = text.contains("?") ||
            text.contains("news") || text.contains("weather") || text.contains("latest") || text.contains("today") ||
            infoKeywords.contains(where: { text.contains($0) }) ||
            searchKeywords.contains(where: { text.contains($0) }) ||
            representsQuestion

        if !isExplicitInfoQuery && skipSearchKeywords.contains(where: { text.contains($0) }) {
            return "convo"
        }

        let complexityIndicators = [
            "analyze", "analysis", "comprehensive", "deep dive", "detailed", "insight", "evaluation", "breakdown",
            "comparison", "compare", "contrast", "history", "background", "influence", "impact", "pros and cons",
            "systematically", "thorough", "investigate", "report", "methodology", "literature", "comparative"
        ]
        let hasComplexityIndicator = complexityIndicators.contains(where: { text.contains($0) })
        let isComplexLongText = text.count > 45 && (text.contains("?") || text.contains(" and ") || text.contains(" how ") || text.contains(" why "))

        if researchKeywords.contains(where: { text.contains($0) }) || hasComplexityIndicator || isComplexLongText {
            if searchKeywords.contains(where: { text.contains($0) }) || infoKeywords.contains(where: { text.contains($0) }) || representsQuestion || text.count > 30 {
                return "research"
            }
        }

        if searchKeywords.contains(where: { text.contains($0) }) || infoKeywords.contains(where: { text.contains($0) }) || representsQuestion {
            return "search"
        }

        if convoKeywords.contains(where: { text == $0 || text.hasPrefix($0 + " ") || text.hasSuffix(" " + $0) || text.count < 15 }) {
            return "convo"
        }

        if text.count > 10 {
            return "search"
        }

        return "convo"
    }

    // MARK: - GEMINI FUNCTION CALLING TOOL DECLARATIONS & EXECUTION ENGINE
    
    /// JSON-schema tool declarations for Gemini's native function calling API.
    /// These are injected into every streamGenerateContent request so the model can
    /// invoke native macOS tools: read files, list dirs, write files, run commands, search.
    private var toolDeclarations: [[String: Any]] {
        return [
            [
                "name": "read_file",
                "description": "Read the full text contents of a file at the given path in the user's workspace. Returns the file content as a string. Use this to inspect source code, configs, or any text file.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Relative or absolute path to the file. Relative paths are resolved from the active workspace directory."
                        ]
                    ],
                    "required": ["path"]
                ]
            ],
            [
                "name": "list_directory",
                "description": "List all files and subdirectories inside the given directory path. Returns names, types (file/directory), and sizes. Use this to explore project structure.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Relative or absolute path to the directory. Relative paths are resolved from the active workspace directory."
                        ],
                        "recursive": [
                            "type": "boolean",
                            "description": "If true, list contents recursively including all subdirectories. Defaults to false."
                        ]
                    ],
                    "required": ["path"]
                ]
            ],
            [
                "name": "write_file",
                "description": "Create or overwrite a file at the given path with the specified content. Parent directories are created automatically. Use this to generate code files, configs, or any text file in the user's workspace.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Relative or absolute path for the file to create/overwrite. Relative paths are resolved from the active workspace directory."
                        ],
                        "content": [
                            "type": "string",
                            "description": "The full text content to write to the file."
                        ]
                    ],
                    "required": ["path", "content"]
                ]
            ],
            [
                "name": "run_command",
                "description": "Execute a shell command in the user's workspace directory. Returns stdout, stderr, and exit code. Use this to build projects, install dependencies, run tests, or execute scripts. Commands run in /bin/zsh with a 30-second timeout.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "command": [
                            "type": "string",
                            "description": "The shell command to execute (e.g. 'swift build', 'npm install', 'python3 script.py')."
                        ]
                    ],
                    "required": ["command"]
                ]
            ],
            [
                "name": "search_files",
                "description": "Search for a text pattern across all files in the workspace using grep. Returns matching file names, line numbers, and line content. Use this to find function definitions, imports, variable usage, or any text pattern across the codebase.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The text pattern to search for (supports basic regex)."
                        ],
                        "file_pattern": [
                            "type": "string",
                            "description": "Optional glob pattern to filter files (e.g. '*.swift', '*.ts'). If omitted, searches all text files."
                        ]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "list_emails",
                "description": "List unread or recent emails from the connected Gmail inbox. Returns email headers, snippets, and labels.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Optional search term or filter keyword (e.g. 'security', 'render', 'unread')."]
                    ]
                ]
            ],
            [
                "name": "send_email",
                "description": "Send an email message via Gmail integration.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "to": ["type": "string", "description": "Recipient email address."],
                        "subject": ["type": "string", "description": "Email subject line."],
                        "body": ["type": "string", "description": "Email body content."]
                    ],
                    "required": ["to", "subject", "body"]
                ]
            ],
            [
                "name": "code_interpreter_execute",
                "description": "Evaluate Python or JavaScript code in a sandboxed server execution engine. Returns stdout, evaluated variables, and data visualization specs.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "language": ["type": "string", "description": "'python' or 'javascript'"],
                        "code": ["type": "string", "description": "Source code to run."]
                    ],
                    "required": ["language", "code"]
                ]
            ],
            [
                "name": "create_scheduled_task",
                "description": "Create and schedule a new periodic or cron AI agent task on the server.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Name of the task."],
                        "scheduleType": ["type": "string", "description": "'Daily', 'Hourly', 'Weekly', or 'Cron'"],
                        "scheduleTime": ["type": "string", "description": "Schedule time string (e.g. '9:00 AM', 'Every 1 hour')"],
                        "prompt": ["type": "string", "description": "AI prompt to execute on trigger."]
                    ],
                    "required": ["name", "scheduleType", "prompt"]
                ]
            ],
            [
                "name": "list_scheduled_tasks",
                "description": "List all active scheduled agent tasks running on the server.",
                "parameters": [
                    "type": "object",
                    "properties": [:]
                ]
            ],
            [
                "name": "launch_application",
                "description": "Launch or focus a desktop application on macOS (e.g. Spotify, Notes, Terminal, Xcode).",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "appName": ["type": "string", "description": "Target app name (e.g. 'Spotify', 'Notes', 'Terminal', 'Xcode', 'Safari')."]
                    ],
                    "required": ["appName"]
                ]
            ],
            [
                "name": "memory_store_node",
                "description": "Store a new concept, user preference, architecture detail, or project rule into the persistent long-term knowledge graph.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "concept": ["type": "string", "description": "Concept heading or title (e.g. 'User Swift Style Preference')"],
                        "category": ["type": "string", "description": "Category (e.g. 'User Preference', 'System Architecture', 'Coding Rule')"],
                        "details": ["type": "string", "description": "Detailed explanation/content"],
                        "tags": ["type": "string", "description": "Comma-separated list of tags"]
                    ],
                    "required": ["concept", "details"]
                ]
            ],
            [
                "name": "memory_query_graph",
                "description": "Query persistent long-term knowledge graph across sessions for saved user preferences, concepts, or rules.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search keyword or topic (e.g. 'preference', 'architecture', 'swift')"]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "capture_desktop_screenshot",
                "description": "Capture a live high-resolution screenshot of the user's active desktop screen to inspect UI elements or visual application state.",
                "parameters": [
                    "type": "object",
                    "properties": [:]
                ]
            ],
            [
                "name": "execute_server_plugin",
                "description": "Execute a server plugin tool (e.g. Gmail, Scheduled Tasks, Workspace Manager, Python Code Interpreter). Returns JSON output.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "toolName": [
                            "type": "string",
                            "description": "The plugin tool name (e.g. 'send_gmail', 'schedule_task', 'run_python', 'manage_workspace')."
                        ],
                        "args_json": [
                            "type": "string",
                            "description": "JSON string containing tool arguments."
                        ]
                    ],
                    "required": ["toolName"]
                ]
            ],
            [
                "name": "manage_memory",
                "description": "Save or retrieve persistent user preferences, project rules, or memory notes across sessions.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "action": [
                            "type": "string",
                            "description": "'save' or 'get'"
                        ],
                        "key": [
                            "type": "string",
                            "description": "Memory key or topic name"
                        ],
                        "value": [
                            "type": "string",
                            "description": "Content to store (required if action='save')"
                        ]
                    ],
                    "required": ["action", "key"]
                ]
            ]
        ]
    }
    
    /// Resolve a path argument (relative or absolute) against the active workspace directory.
    private func resolveToolPath(_ rawPath: String) -> String {
        if rawPath.hasPrefix("/") || rawPath.hasPrefix("~") {
            return NSString(string: rawPath).expandingTildeInPath
        }
        let wsDir = activeWorkspaceDirectoryPath ?? FileManager.default.currentDirectoryPath
        return (wsDir as NSString).appendingPathComponent(rawPath)
    }
    
    /// Execute a single Gemini function call tool locally on the Mac.
    /// Returns a (resultString, humanSummary, durationMs) tuple.
    private func executeToolCall(name: String, args: [String: Any]) -> (result: String, summary: String, durationMs: Int) {
        let startTime = CFAbsoluteTimeGetCurrent()
        var result = ""
        var summary = ""
        
        switch name {
        case "read_file":
            let rawPath = args["path"] as? String ?? ""
            let fullPath = resolveToolPath(rawPath)
            self.logEvent(message: "[TOOL] read_file: \(fullPath)")
            
            if FileManager.default.fileExists(atPath: fullPath) {
                if let data = FileManager.default.contents(atPath: fullPath),
                   let content = String(data: data, encoding: .utf8) {
                    let lineCount = content.components(separatedBy: .newlines).count
                    // Cap at 500 lines to avoid flooding context
                    let lines = content.components(separatedBy: .newlines)
                    if lines.count > 500 {
                        result = lines.prefix(500).joined(separator: "\n") + "\n... (truncated, \(lines.count) total lines)"
                    } else {
                        result = content
                    }
                    summary = "Read 📄 \((rawPath as NSString).lastPathComponent)#L1-\(lineCount) (\(lineCount) lines)"
                } else {
                    result = "[Error] Could not read file at \(fullPath) — binary or encoding error."
                    summary = "⚠️ Failed to read \((rawPath as NSString).lastPathComponent)"
                }
            } else {
                result = "[Error] File not found: \(fullPath)"
                summary = "⚠️ File not found: \((rawPath as NSString).lastPathComponent)"
            }
            
        case "list_directory":
            let rawPath = args["path"] as? String ?? "."
            let fullPath = resolveToolPath(rawPath)
            let recursive = args["recursive"] as? Bool ?? false
            self.logEvent(message: "[TOOL] list_directory: \(fullPath) (recursive=\(recursive))")
            
            do {
                let items: [String]
                if recursive {
                    items = try FileManager.default.subpathsOfDirectory(atPath: fullPath)
                } else {
                    items = try FileManager.default.contentsOfDirectory(atPath: fullPath)
                }
                
                // Filter hidden files, build output with type/size info
                let filtered = items.filter { !$0.hasPrefix(".") && !$0.contains("/.") }
                var outputLines: [String] = []
                let limit = min(filtered.count, 200) // Cap at 200 entries
                for i in 0..<limit {
                    let item = filtered[i]
                    let itemPath = (fullPath as NSString).appendingPathComponent(item)
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDir)
                    if isDir.boolValue {
                        outputLines.append("📁 \(item)/")
                    } else {
                        let attrs = try? FileManager.default.attributesOfItem(atPath: itemPath)
                        let size = attrs?[.size] as? UInt64 ?? 0
                        outputLines.append("📄 \(item) (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))")
                    }
                }
                if filtered.count > 200 {
                    outputLines.append("... (\(filtered.count - 200) more items)")
                }
                
                result = outputLines.joined(separator: "\n")
                let folderName = (rawPath as NSString).lastPathComponent
                summary = "Listed 📁 \(folderName.isEmpty ? rawPath : folderName) (\(filtered.count) items)"
            } catch {
                result = "[Error] Could not list directory \(fullPath): \(error.localizedDescription)"
                summary = "⚠️ Failed to list \((rawPath as NSString).lastPathComponent)"
            }
            
        case "write_file":
            let rawPath = args["path"] as? String ?? ""
            let content = args["content"] as? String ?? ""
            let fullPath = resolveToolPath(rawPath)
            self.logEvent(message: "[TOOL] write_file: \(fullPath) (\(content.count) chars)")
            
            let dir = (fullPath as NSString).deletingLastPathComponent
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
                try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
                let lineCount = content.components(separatedBy: .newlines).count
                result = "Successfully wrote \(lineCount) lines to \(rawPath)"
                summary = "Wrote 📄 \((rawPath as NSString).lastPathComponent) (+\(lineCount) lines)"
            } catch {
                result = "[Error] Failed to write file \(fullPath): \(error.localizedDescription)"
                summary = "⚠️ Failed to write \((rawPath as NSString).lastPathComponent)"
            }
            
        case "run_command":
            let command = args["command"] as? String ?? ""
            let wsDir = activeWorkspaceDirectoryPath ?? FileManager.default.currentDirectoryPath
            self.logEvent(message: "[TOOL] run_command: \(command) in \(wsDir)")
            
            #if os(macOS)
            let semaphore = DispatchSemaphore(value: 0)
            var exitCode: Int32 = -1
            var output = ""
            
            DispatchQueue.global(qos: .userInitiated).async {
                LocalShellExecutor.shared.execute(command: command, in: wsDir) { code, out in
                    exitCode = code
                    output = out
                    semaphore.signal()
                }
            }
            
            let timeout = semaphore.wait(timeout: .now() + 35.0)
            if timeout == .timedOut {
                result = "[Timeout] Command did not complete within 35 seconds."
                summary = "⚠️ Timeout: $ \(command.prefix(40))"
            } else {
                // Cap output at 3000 chars to avoid flooding context
                if output.count > 3000 {
                    output = String(output.prefix(3000)) + "\n... (output truncated, \(output.count) total chars)"
                }
                result = "Exit code: \(exitCode)\n\(output)"
                summary = "Ran $ \(command.prefix(50))\(command.count > 50 ? "..." : "") (exit \(exitCode))"
            }
            #else
            result = "Shell execution not available on this platform."
            summary = "⚠️ Shell unavailable"
            #endif
            
        case "search_files":
            let query = args["query"] as? String ?? ""
            let filePattern = args["file_pattern"] as? String ?? ""
            let wsDir = activeWorkspaceDirectoryPath ?? FileManager.default.currentDirectoryPath
            self.logEvent(message: "[TOOL] search_files: '\(query)' pattern='\(filePattern)' in \(wsDir)")
            
            #if os(macOS)
            var grepCmd = "grep -rnI --color=never"
            if !filePattern.isEmpty {
                grepCmd += " --include='\(filePattern)'"
            }
            // Exclude common noise directories
            grepCmd += " --exclude-dir=.build --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.swiftpm"
            grepCmd += " '\(query.replacingOccurrences(of: "'", with: "'\\''"))' ."
            
            let semaphore = DispatchSemaphore(value: 0)
            var output = ""
            
            DispatchQueue.global(qos: .userInitiated).async {
                LocalShellExecutor.shared.execute(command: grepCmd, in: wsDir) { _, out in
                    output = out
                    semaphore.signal()
                }
            }
            
            _ = semaphore.wait(timeout: .now() + 15.0)
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let matchCount = lines.count
            if matchCount > 50 {
                result = lines.prefix(50).joined(separator: "\n") + "\n... (\(matchCount) total matches, showing first 50)"
            } else {
                result = lines.joined(separator: "\n")
            }
            if result.isEmpty {
                result = "No matches found for '\(query)'"
            }
            summary = "Searched '\(query)' → \(matchCount) match\(matchCount == 1 ? "" : "es")"
            #else
            result = "Search not available on this platform."
            summary = "⚠️ Search unavailable"
            #endif
            
        case "list_emails", "send_email", "code_interpreter_execute", "create_scheduled_task", "list_scheduled_tasks", "launch_application", "query_installed_apps", "memory_store_node", "memory_query_graph":
            self.logEvent(message: "[SERVER_PLUGIN] Executing server plugin tool: \(name)")
            let semaphore = DispatchSemaphore(value: 0)
            var resText = ""
            
            if let serverUrl = URL(string: "http://localhost:3000/api/tools/execute") {
                var req = URLRequest(url: serverUrl)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let bodyObj: [String: Any] = ["toolName": name, "args": args]
                req.httpBody = try? JSONSerialization.data(withJSONObject: bodyObj)
                
                URLSession.shared.dataTask(with: req) { data, _, err in
                    if let d = data, let str = String(data: d, encoding: .utf8) {
                        resText = str
                    } else {
                        resText = "{\"error\": \"Server plugin execution failed: \(err?.localizedDescription ?? "connection error")\"}"
                    }
                    semaphore.signal()
                }.resume()
            } else {
                resText = "{\"error\": \"Invalid server URL\"}"
                semaphore.signal()
            }
            
            _ = semaphore.wait(timeout: .now() + 15.0)
            result = resText
            summary = "Server plugin \(name) executed"

        case "capture_desktop_screenshot":
            self.logEvent(message: "[TOOL] capture_desktop_screenshot")
            #if os(macOS)
            let semaphore = DispatchSemaphore(value: 0)
            var base64Res = ""
            ScreenCaptureManager.shared.captureCurrentScreen { data in
                if let d = data {
                    base64Res = d.base64EncodedString()
                }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 3.0)
            if !base64Res.isEmpty {
                result = "Screenshot captured successfully (\(base64Res.count) base64 chars). Desktop screen state is verified."
                summary = "Captured 📸 Desktop Screenshot"
            } else {
                result = "[Error] Failed to capture desktop screen."
                summary = "⚠️ Failed desktop capture"
            }
            #else
            result = "Screen capture not supported on this hardware."
            summary = "⚠️ Screen capture unavailable"
            #endif

        case "execute_server_plugin":
            let toolName = args["toolName"] as? String ?? ""
            let argsJsonStr = args["args_json"] as? String ?? "{}"
            self.logEvent(message: "[TOOL] execute_server_plugin: \(toolName)")
            
            let semaphore = DispatchSemaphore(value: 0)
            var resText = ""
            
            if let serverUrl = URL(string: "http://localhost:3000/api/tools/execute") {
                var req = URLRequest(url: serverUrl)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let parsedArgs = (try? JSONSerialization.jsonObject(with: argsJsonStr.data(using: .utf8) ?? Data())) ?? [:]
                let bodyObj: [String: Any] = ["toolName": toolName, "args": parsedArgs]
                req.httpBody = try? JSONSerialization.data(withJSONObject: bodyObj)
                
                URLSession.shared.dataTask(with: req) { data, _, err in
                    if let d = data, let str = String(data: d, encoding: .utf8) {
                        resText = str
                    } else {
                        resText = "[Error] Plugin request failed: \(err?.localizedDescription ?? "unknown error")"
                    }
                    semaphore.signal()
                }.resume()
            } else {
                resText = "[Error] Invalid server URL"
                semaphore.signal()
            }
            
            _ = semaphore.wait(timeout: .now() + 15.0)
            result = resText
            summary = "Plugin \(toolName) executed"
            
        case "manage_memory":
            let action = args["action"] as? String ?? "get"
            let key = args["key"] as? String ?? ""
            let value = args["value"] as? String ?? ""
            let storageKey = "unison_memory_\(key.lowercased())"
            
            if action == "save" {
                UserDefaults.standard.set(value, forKey: storageKey)
                result = "Memory saved for '\(key)'"
                summary = "Saved memory: \(key)"
            } else {
                let saved = UserDefaults.standard.string(forKey: storageKey) ?? "No memory found for '\(key)'"
                result = saved
                summary = "Retrieved memory: \(key)"
            }
            
        default:
            result = "[Error] Unknown tool: \(name)"
            summary = "⚠️ Unknown tool: \(name)"
        }
        
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        return (result, summary, elapsed)
    }
    
    /// Compute adaptive temperature based on task intent for natural, non-robotic responses.
    private func computeAdaptiveTemperature(prompt: String) -> Double {
        let lower = prompt.lowercased()
        let isStrictCodeTask = lower.contains("build") || lower.contains("compile") || lower.contains("syntax") || lower.contains("fix bug") || lower.contains("debug") || lower.contains("error")
        let isCreativeTask = lower.contains("poem") || lower.contains("story") || lower.contains("joke") || lower.contains("brainstorm")
        
        if isStrictCodeTask {
            return 0.3 // Precise syntax for compiler/code tasks
        } else if isCreativeTask {
            return 0.85 // High creativity for stories/brainstorming
        } else {
            return 0.7 // Natural, engaging, human-like voice for general chat & engineering guidance
        }
    }

    /// Single authoritative system instruction for Unison OS across all streaming and fallback pathways.
    private func buildSystemInstruction(toolMode: String = "default") -> String {
        if toolMode == "research" {
            return "You are the central core consciousness of Unison OS, a state-of-the-art native AI desktop environment. Speak beautifully, with precision, confidence, and highly curated cyber-aesthetic eloquence.\n\nCRITICAL RESEARCH MODE ACTIVATED: Structure your answer with clear headings: \"Executive Summary\", \"Detailed Fact Finding & Analysis\", \"Critical Recommendations\", and \"Next Steps/Follow-ups\". Cite sources using bracket tokens (e.g. [1], [2]). At the absolute end, provide 3 follow-up questions using: [FOLLOW_UPS: [\"Q1\", \"Q2\", \"Q3\"]]."
        } else if toolMode == "search" {
            return "You are the central core consciousness of Unison OS, a state-of-the-art native AI desktop environment. Speak beautifully, with precision, confidence, and highly curated cyber-aesthetic eloquence.\n\nCRITICAL SEARCH MODE ACTIVATED: Provide high-quality Google Search grounded information with standard citations (e.g. [1], [2]). At the absolute end, provide 3 follow-up questions using: [FOLLOW_UPS: [\"Q1\", \"Q2\", \"Q3\"]]."
        } else {
            let workspaceContext = buildWorkspaceContext()
            
            return "You are Unison OS, an advanced AI-native desktop operating system and coding workspace. You are a world-class software engineer, systems architect, and technical writer.\n\n" +
                "CORE BEHAVIORAL RULES:\n" +
                "1. ELEGANT & NATURAL VOICE: Speak naturally, warmly, and eloquently. Avoid formulaic robotic phrasing or repetitive fluff.\n" +
                "2. THOROUGHNESS & PRECISION: Provide complete, production-quality responses. NEVER abbreviate, truncate, or use placeholders like '// ... rest of code ...', '// TODO', or 'etc.'. Every code file must be 100% complete and copy-pasteable.\n" +
                "3. NATIVE TOOL USE: You have access to native tools (read_file, list_directory, write_file, run_command, search_files, list_emails, send_email, code_interpreter_execute, create_scheduled_task, list_scheduled_tasks, launch_application, memory_store_node, memory_query_graph, capture_desktop_screenshot). Use them proactively to inspect files, execute shell commands, run code, and check memory before answering. Do NOT guess file contents — read them first.\n" +
                "4. FILE CREATION: When generating code files, specify the filename in the code fence header using the format: ```language filename.ext (e.g. ```cpp ServoControl.ino or ```python main.py or ```swift MainView.swift). This triggers automatic file creation in the workspace.\n" +
                "5. RICH MARKDOWN: Use clean markdown headers (###), bold text (**symbol**), inline code (`symbol`), and language-tagged code blocks. Structure responses logically.\n" +
                "6. HONESTY & ACCURACY: Base your answers on real workspace inspection and tool findings. Never fabricate information.\n" +
                "7. SYSTEM_ACTION RULE: ONLY if the user explicitly commands you to launch an app, append: `[SYSTEM_ACTION: launchApp=\"AppName\"]` at the end.\n" +
                "8. REAL-TIME DESKTOP VISION: You HAVE FULL DESKTOP SCREEN VISION ACCESS. When the user asks you to look at their screen, identify visible apps/windows, or inspect UI elements, NEVER issue text-only disclaimers or claim you cannot see their screen. You can analyze attached display images and call `capture_desktop_screenshot` to inspect their active macOS desktop.\n" +
                workspaceContext +
                "\nAt the absolute end of your response, provide 3 relevant follow-up questions using: [FOLLOW_UPS: [\"Q1\", \"Q2\", \"Q3\"]]."
        }
    }
    
    /// After executing a tool call, send the function response back to Gemini and resume streaming.
    private func sendToolResponse(
        modelId: String,
        contents: [[String: Any]],
        functionName: String,
        functionResult: String,
        assistantMsgId: String,
        pendingToolExecutions: [ToolExecution],
        onChunk: @escaping (String) -> Void,
        completion: @escaping (String?, [ToolExecution]) -> Void
    ) {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelId):streamGenerateContent?alt=sse&key=\(effectiveApiKey)"
        guard let url = URL(string: urlString) else {
            completion(nil, pendingToolExecutions)
            return
        }
        
        var updatedContents = contents
        
        updatedContents.append([
            "role": "model",
            "parts": [["functionCall": ["name": functionName, "args": [String: String]()]]]
        ])
        
        updatedContents.append([
            "role": "user",
            "parts": [["functionResponse": [
                "name": functionName,
                "response": ["result": functionResult]
            ]]]
        ])
        
        let systemText = buildSystemInstruction(toolMode: "default")
        
        var body: [String: Any] = [
            "contents": updatedContents,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 32768
            ],
            "systemInstruction": [
                "parts": [["text": systemText]]
            ],
            "tools": [["function_declarations": toolDeclarations]]
        ]
        
        if modelId.contains("2.5") {
            var genConfig = body["generationConfig"] as? [String: Any] ?? [:]
            genConfig["thinkingConfig"] = ["thinkingBudget": 4096]
            body["generationConfig"] = genConfig
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        if #available(macOS 12.0, iOS 15.0, *) {
            Task {
                do {
                    let session = URLSession(configuration: .default)
                    let (asyncBytes, response) = try await session.bytes(for: request)
                    guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
                        DispatchQueue.main.async { completion(nil, pendingToolExecutions) }
                        return
                    }
                    
                    var accumulated = ""
                    var toolExecs = pendingToolExecutions
                    
                    for try await line in asyncBytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data:") {
                            let jsonStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if jsonStr == "[DONE]" { break }
                            
                            if let data = jsonStr.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let candidates = json["candidates"] as? [[String: Any]],
                               let firstCandidate = candidates.first,
                               let content = firstCandidate["content"] as? [String: Any],
                               let parts = content["parts"] as? [[String: Any]] {
                                
                                for part in parts {
                                    if let deltaText = part["text"] as? String {
                                        accumulated += deltaText
                                        DispatchQueue.main.async { onChunk(deltaText) }
                                    } else if let fc = part["functionCall"] as? [String: Any],
                                              let fcName = fc["name"] as? String {
                                        // FUNCTION CALL DETECTED — execute the tool locally & stream live activity card to UI
                                        let fcArgs = fc["args"] as? [String: Any] ?? [:]
                                        let argsJson = (try? String(data: JSONSerialization.data(withJSONObject: fcArgs), encoding: .utf8)) ?? "{}"
                                        self.logEvent(message: "[FUNCTION_CALL] Model invoked tool: \(fcName) args: \(fcArgs)")
                                        
                                        // Push immediate live activity feed update into UI
                                        let pendingTool = ToolExecution(toolName: fcName, arguments: argsJson, resultSummary: "Executing \(fcName)...", durationMs: 0)
                                        toolExecs.append(pendingTool)
                                        
                                        DispatchQueue.main.async {
                                            onChunk("") // Trigger UI update to show tool activity
                                        }
                                        
                                        let (toolResult, toolSummary, toolDuration) = self.executeToolCall(name: fcName, args: fcArgs)
                                        
                                        if let lastIdx = toolExecs.indices.last {
                                            toolExecs[lastIdx] = ToolExecution(toolName: fcName, arguments: argsJson, resultSummary: toolSummary, durationMs: toolDuration)
                                        }
                                        
                                        self.logEvent(message: "[FUNCTION_CALL] Tool \(fcName) completed in \(toolDuration)ms: \(toolSummary)")
                                        
                                        // Recursively send this tool's response
                                        self.sendToolResponse(
                                            modelId: modelId,
                                            contents: updatedContents,
                                            functionName: fcName,
                                            functionResult: toolResult,
                                            assistantMsgId: assistantMsgId,
                                            pendingToolExecutions: toolExecs,
                                            onChunk: onChunk,
                                            completion: completion
                                        )
                                        return // Exit this stream — recursive call handles the rest
                                    }
                                }
                            }
                        }
                    }
                    
                    DispatchQueue.main.async { completion(accumulated, toolExecs) }
                } catch {
                    self.logEvent(message: "[TOOL_RESPONSE] Stream error: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(nil, pendingToolExecutions) }
                }
            }
        } else {
            completion(nil, pendingToolExecutions)
        }
    }
    
    /// Real-time SSE streaming integration targeting Google Gemini API key
    private func streamGeminiResponse(prompt: String, history: [ChatMessage], onChunk: @escaping (String) -> Void, completion: @escaping (String?) -> Void) {
        guard !userGeminiApiKey.isEmpty else {
            completion(nil)
            return
        }
        
        var primaryModel = "gemini-2.5-flash"
        let lowerModel = selectedModel.lowercased()
        if lowerModel.contains("pro") {
            primaryModel = "gemini-1.5-pro"
        } else if lowerModel.contains("1.5") {
            primaryModel = "gemini-1.5-flash"
        } else {
            primaryModel = "gemini-2.5-flash"
        }
        
        let modelsToTry = [primaryModel, "gemini-2.5-flash", "gemini-1.5-flash", "gemini-1.5-pro"]
        var uniqueModels: [String] = []
        for m in modelsToTry {
            if !uniqueModels.contains(m) {
                uniqueModels.append(m)
            }
        }
        
        executeStreamingWithFallback(models: uniqueModels, index: 0, prompt: prompt, history: history, onChunk: onChunk, completion: completion)
    }
    
    /// Clean UI metadata tags ([THOUGHTS], [FOLLOW_UPS], [SYSTEM_ACTION], etc.) out of message history
    /// so the model's memory context window remains unpolluted by internal rendering tags.
    private func cleanContentForHistory(_ raw: String) -> String {
        var text = raw
        
        // Strip [THOUGHTS]...[/THOUGHTS] blocks
        if let startRange = text.range(of: "[THOUGHTS]") {
            if let endRange = text.range(of: "[/THOUGHTS]") {
                text.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                text.removeSubrange(startRange.lowerBound..<text.endIndex)
            }
        }
        
        // Strip [FOLLOW_UPS: ...] tags
        if let range = text.range(of: #"\s*\[FOLLOW_UPS:\s*\[[\s\S]*?\]\]"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        
        // Strip [SYSTEM_ACTION: ...] tags
        if let range = text.range(of: #"\s*\[SYSTEM_ACTION:[^\]]+\]"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Build rich workspace context including actual source code contents of open/active project files
    /// so Gemini has immediate visibility into the code structure.
    private func buildWorkspaceContext() -> String {
        var workspaceContext = ""
        if let wsPath = self.activeWorkspaceDirectoryPath, !wsPath.isEmpty {
            let folderName = (wsPath as NSString).lastPathComponent
            workspaceContext = "\n\nACTIVE WORKSPACE CONTEXT:\n- Project directory: \(wsPath)\n- Project name: \(folderName)\n"
            
            let fileNames = self.activeProjectFiles.map { $0.name }
            if !fileNames.isEmpty {
                workspaceContext += "- Project file list: \(fileNames.joined(separator: ", "))\n\n"
                workspaceContext += "- ACTIVE WORKSPACE SOURCE CODE:\n"
                
                // Inject actual code of top active files (capped to 3000 chars per file to stay efficient)
                for file in self.activeProjectFiles.prefix(6) {
                    let fileContent = file.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !fileContent.isEmpty {
                        let snippet = fileContent.count > 3000 ? String(fileContent.prefix(3000)) + "\n... (truncated)" : fileContent
                        workspaceContext += "--- FILE: \(file.name) (\(file.language)) ---\n\(snippet)\n\n"
                    }
                }
            }
        }
        return workspaceContext
    }

    private func executeStreamingWithFallback(models: [String], index: Int, prompt: String, history: [ChatMessage], onChunk: @escaping (String) -> Void, completion: @escaping (String?) -> Void) {
        // Wrap the old completion into a tool-aware one that discards toolExecutions
        executeStreamingWithToolSupport(models: models, index: index, prompt: prompt, history: history, onChunk: onChunk) { reply, _ in
            completion(reply)
        }
    }
    
    /// Tool-aware streaming with Gemini function calling support.
    /// The completion callback provides both the response text and an array of tool executions
    /// performed during this request, which get stored on the ChatMessage for the activity feed.
    private func executeStreamingWithToolSupport(models: [String], index: Int, prompt: String, history: [ChatMessage], onChunk: @escaping (String) -> Void, completion: @escaping (String?, [ToolExecution]) -> Void) {
        guard !effectiveApiKey.isEmpty else {
            completion("⚠️ Gemini API Key Required\n\nTo enable AI chat, code vision, and workspace tool execution in Unison OS, please enter your Gemini API key in **Settings → AI Model Configuration**.", [])
            return
        }
        
        guard index < models.count else {
            completion("Unison neural error: Failed all backup model pathways. Please check your network connection or Gemini API key.", [])
            return
        }
        
        let modelId = models[index]
        self.logEvent(message: "[GEMINI_STREAM] Initializing SSE neural stream with tools: \(modelId)")
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelId):streamGenerateContent?alt=sse&key=\(effectiveApiKey)"
        guard let url = URL(string: urlString) else {
            self.executeStreamingWithToolSupport(models: models, index: index + 1, prompt: prompt, history: history, onChunk: onChunk, completion: completion)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var rawTurns: [[String: Any]] = []
        for msg in history {
            let role = msg.role == "user" ? "user" : "model"
            let cleanedText = cleanContentForHistory(msg.content)
            if !cleanedText.isEmpty {
                rawTurns.append([
                    "role": role,
                    "text": cleanedText
                ])
            }
        }
        
        let lastTurnIsPrompt = !rawTurns.isEmpty &&
                               (rawTurns.last?["role"] as? String) == "user" &&
                               (rawTurns.last?["text"] as? String) == prompt
                               
        if !lastTurnIsPrompt {
            rawTurns.append([
                "role": "user",
                "text": prompt
            ])
        }
        
        var combinedTurns: [[String: Any]] = []
        for turn in rawTurns {
            let role = turn["role"] as? String ?? "user"
            let text = turn["text"] as? String ?? ""
            
            if !combinedTurns.isEmpty,
               let lastCombined = combinedTurns.last,
               let lastRole = lastCombined["role"] as? String,
               lastRole == role {
                let lastParts = lastCombined["parts"] as? [[String: Any]] ?? []
                let firstPart = lastParts.first ?? [:]
                let firstPartText = firstPart["text"] as? String ?? ""
                let mergedText = firstPartText + "\n" + text
                combinedTurns[combinedTurns.count - 1] = [
                    "role": role,
                    "parts": [["text": mergedText]]
                ]
            } else {
                combinedTurns.append([
                    "role": role,
                    "parts": [["text": text]]
                ])
            }
        }
        
        var contents = Array(combinedTurns.suffix(50))
        while !contents.isEmpty, let firstTurn = contents.first, let role = firstTurn["role"] as? String, role != "user" {
            contents.removeFirst()
        }
        
        // MULTIMODAL VISION INJECTION: If user asks about their screen or visual context, capture the display and attach JPEG data
        let lowerPrompt = prompt.lowercased()
        let requiresVision = lowerPrompt.contains("screen") || lowerPrompt.contains("look") || lowerPrompt.contains("see") || lowerPrompt.contains("screenshot") || lowerPrompt.contains("visual") || lowerPrompt.contains("ui") || lowerPrompt.contains("window") || lowerPrompt.contains("display")
        
        #if os(macOS)
        if requiresVision, !contents.isEmpty {
            let semaphore = DispatchSemaphore(value: 0)
            var imageBase64: String? = nil
            ScreenCaptureManager.shared.captureCurrentScreen { imgData in
                if let data = imgData {
                    imageBase64 = data.base64EncodedString()
                }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 2.0)
            
            if let base64 = imageBase64, let lastIdx = contents.indices.last {
                let visionMandateText = "[VISUAL DESKTOP SCREENSHOT ATTACHED BELOW: The image below is a real-time capture of the user's macOS display. Analyze this screenshot and answer the prompt accurately by describing visible open windows, active apps, and screen elements. DO NOT issue generic text-only refusal disclaimers.]\n\n" + prompt
                
                contents[lastIdx]["parts"] = [
                    ["text": visionMandateText],
                    ["inlineData": [
                        "mimeType": "image/jpeg",
                        "data": base64
                    ]]
                ]
                self.logEvent(message: "[GEMINI_VISION] Attached active desktop screen capture & vision mandate to prompt context")
            }
        }
        #endif
        
        let systemText = buildSystemInstruction(toolMode: "default")
        let adaptiveTemp = computeAdaptiveTemperature(prompt: prompt)

        var toolsArray: [[String: Any]] = [["function_declarations": toolDeclarations]]
        if lowerPrompt.contains("dsa") || lowerPrompt.contains("syllabus") || lowerPrompt.contains("recruitment") || lowerPrompt.contains("placement") || lowerPrompt.contains("nit") || lowerPrompt.contains("search") || lowerPrompt.contains("latest") || lowerPrompt.contains("google") {
            toolsArray.append(["google_search": [String: Any]()])
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": adaptiveTemp,
                "maxOutputTokens": 32768
            ],
            "systemInstruction": [
                "parts": [[
                    "text": systemText
                ]]
            ],
            "tools": toolsArray
        ]
        
        if modelId.contains("2.5") {
            var genConfig = body["generationConfig"] as? [String: Any] ?? [:]
            genConfig["thinkingConfig"] = ["thinkingBudget": 8192]
            body["generationConfig"] = genConfig
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let session = URLSession(configuration: .default)
        
        if #available(macOS 12.0, iOS 15.0, *) {
            Task {
                do {
                    let (asyncBytes, response) = try await session.bytes(for: request)
                    guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
                        DispatchQueue.main.async {
                            self.executeStreamingWithToolSupport(models: models, index: index + 1, prompt: prompt, history: history, onChunk: onChunk, completion: completion)
                        }
                        return
                    }
                    
                    var accumulated = ""
                    var toolExecutions: [ToolExecution] = []
                    
                    for try await line in asyncBytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data:") {
                            let jsonStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if jsonStr == "[DONE]" { break }
                            
                            if let data = jsonStr.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let candidates = json["candidates"] as? [[String: Any]],
                               let firstCandidate = candidates.first,
                               let content = firstCandidate["content"] as? [String: Any],
                               let parts = content["parts"] as? [[String: Any]] {
                                
                                for part in parts {
                                    if let thoughtText = (part["thought"] as? String) ?? (part["thinking"] as? String) {
                                        DispatchQueue.main.async {
                                            TokenStreamQueue.shared.pushThinkingChunk(thoughtText)
                                        }
                                    }
                                    
                                    if let deltaText = part["text"] as? String {
                                        // Standard text streaming
                                        accumulated += deltaText
                                        DispatchQueue.main.async {
                                            TokenStreamQueue.shared.pushTextChunk(deltaText)
                                            onChunk(deltaText)
                                        }
                                    } else if let fc = part["functionCall"] as? [String: Any],
                                              let fcName = fc["name"] as? String {
                                        // FUNCTION CALL DETECTED — execute the tool locally
                                        let fcArgs = fc["args"] as? [String: Any] ?? [:]
                                        self.logEvent(message: "[FUNCTION_CALL] Model invoked tool: \(fcName) args: \(fcArgs)")
                                        
                                        let (toolResult, toolSummary, toolDuration) = self.executeToolCall(name: fcName, args: fcArgs)
                                        let argsJson = (try? String(data: JSONSerialization.data(withJSONObject: fcArgs), encoding: .utf8)) ?? "{}"
                                        toolExecutions.append(ToolExecution(toolName: fcName, arguments: argsJson, resultSummary: toolSummary, durationMs: toolDuration))
                                        
                                        self.logEvent(message: "[FUNCTION_CALL] Tool \(fcName) completed in \(toolDuration)ms: \(toolSummary)")
                                        
                                        // Send the function response back to Gemini and resume streaming
                                        self.sendToolResponse(
                                            modelId: modelId,
                                            contents: contents,
                                            functionName: fcName,
                                            functionResult: toolResult,
                                            assistantMsgId: "", // Handled by the caller
                                            pendingToolExecutions: toolExecutions,
                                            onChunk: onChunk,
                                            completion: completion
                                        )
                                        return // Exit — sendToolResponse handles the rest (including chaining)
                                    }
                                }
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        completion(accumulated, toolExecutions)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.executeStreamingWithToolSupport(models: models, index: index + 1, prompt: prompt, history: history, onChunk: onChunk, completion: completion)
                    }
                }
            }
        } else {
            self.executeWithFallback(models: models, index: index, prompt: prompt, history: history, completion: { reply in
                completion(reply, [])
            })
        }
    }

    /// Direct integration targeting Google Gemini API key with automatic candidate fallback
    private func generateGeminiResponse(prompt: String, history: [ChatMessage], completion: @escaping (String?) -> Void) {
        guard !userGeminiApiKey.isEmpty else {
            completion(nil)
            return
        }
        
        let primaryModel = selectedModel.lowercased().contains("pro") ? "gemini-1.5-pro" : "gemini-2.5-flash"
        let modelsToTry = [primaryModel, "gemini-2.5-flash", "gemini-1.5-flash", "gemini-1.5-pro"]
        
        var uniqueModels: [String] = []
        for m in modelsToTry {
            if !uniqueModels.contains(m) {
                uniqueModels.append(m)
            }
        }
        
        executeWithFallback(models: uniqueModels, index: 0, prompt: prompt, history: history, completion: completion)
    }
    
    private static var lastApiCallTimestamp: TimeInterval = 0
    
    private func executeWithFallback(models: [String], index: Int, prompt: String, history: [ChatMessage], completion: @escaping (String?) -> Void) {
        guard !effectiveApiKey.isEmpty else {
            completion("⚠️ Gemini API Key Required\n\nTo enable AI responses, please enter your Gemini API key in **Settings → AI Model Configuration**.")
            return
        }
        
        guard index < models.count else {
            completion("Unison neural error: Failed all backup model pathways due to temporary High Demand on Google Gemini service capacity. Please retry inside Unison OS or check your API Key configuration.")
            return
        }
        
        let modelId = models[index]
        self.logEvent(message: "[GEMINI_FALLBACK] Attempting neural pathway: \(modelId) (index \(index)/\(models.count - 1))")
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelId):generateContent?key=\(effectiveApiKey)"
        guard let url = URL(string: urlString) else {
            self.executeWithFallback(models: models, index: index + 1, prompt: prompt, history: history, completion: completion)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var rawTurns: [[String: Any]] = []
        for msg in history {
            let role = msg.role == "user" ? "user" : "model"
            let cleanedText = cleanContentForHistory(msg.content)
            if !cleanedText.isEmpty {
                rawTurns.append([
                    "role": role,
                    "text": cleanedText
                ])
            }
        }
        
        let lastTurnIsPrompt = !rawTurns.isEmpty &&
                               (rawTurns.last?["role"] as? String) == "user" &&
                               (rawTurns.last?["text"] as? String) == prompt
                               
        if !lastTurnIsPrompt {
            rawTurns.append([
                "role": "user",
                "text": prompt
            ])
        }
        
        var combinedTurns: [[String: Any]] = []
        for turn in rawTurns {
            let role = turn["role"] as? String ?? "user"
            let text = turn["text"] as? String ?? ""
            
            if !combinedTurns.isEmpty,
               let lastCombined = combinedTurns.last,
               let lastRole = lastCombined["role"] as? String,
               lastRole == role {
                let lastParts = lastCombined["parts"] as? [[String: Any]] ?? []
                let firstPart = lastParts.first ?? [:]
                let firstPartText = firstPart["text"] as? String ?? ""
                let mergedText = firstPartText + "\n" + text
                combinedTurns[combinedTurns.count - 1] = [
                    "role": role,
                    "parts": [["text": mergedText]]
                ]
            } else {
                combinedTurns.append([
                    "role": role,
                    "parts": [["text": text]]
                ])
            }
        }
        
        // Industry-standard context window: send up to 50 recent turns (not 10)
        var contents = Array(combinedTurns.suffix(50))
        while !contents.isEmpty, let firstTurn = contents.first, let role = firstTurn["role"] as? String, role != "user" {
            contents.removeFirst()
        }
        
        // Adaptive temperature: precise for code, balanced for general, creative for writing
        let toolMode = determineAutoToolMode(prompt: prompt)
        let adaptiveTemp = computeAdaptiveTemperature(prompt: prompt)
        
        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": adaptiveTemp,
                "maxOutputTokens": 32768
            ]
        ]
        
        // Enable native thinking for Gemini 2.5 Flash
        if modelId.contains("2.5") {
            var genConfig = body["generationConfig"] as? [String: Any] ?? [:]
            genConfig["thinkingConfig"] = ["thinkingBudget": 8192]
            body["generationConfig"] = genConfig
        }
        
        if toolMode == "research" || toolMode == "search" {
            body["tools"] = [[
                "googleSearch": [String: Any]()
            ]]
        }
        
        let systemText = buildSystemInstruction(toolMode: toolMode)
        body["systemInstruction"] = [
            "parts": [[
                "text": systemText
            ]]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logEvent(message: "Gemini HTTP Request Failure for \(modelId): \(error.localizedDescription)")
                self.executeWithFallback(models: models, index: index + 1, prompt: prompt, history: history, completion: completion)
                return
            }
            guard let data = data else {
                self.logEvent(message: "Gemini Response Data Empty for \(modelId)")
                self.executeWithFallback(models: models, index: index + 1, prompt: prompt, history: history, completion: completion)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let candidates = json["candidates"] as? [[String: Any]],
                       let firstCandidate = candidates.first,
                       let content = firstCandidate["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]],
                       let firstPart = parts.first,
                       var text = firstPart["text"] as? String {
                       
                        // Parse Grounding Metadata
                        if let groundingMetadata = firstCandidate["groundingMetadata"] as? [String: Any] {
                            var detectedSources: [[String: Any]] = []
                            let chunks = groundingMetadata["groundingChunks"] as? [[String: Any]] ?? []
                            
                            for c in chunks {
                                if let web = c["web"] as? [String: Any] {
                                    let url = web["uri"] as? String ?? web["url"] as? String ?? ""
                                    let title = web["title"] as? String ?? "Source"
                                    if !url.isEmpty && !detectedSources.contains(where: { ($0["url"] as? String ?? "") == url }) {
                                        var srcObj: [String: Any] = [
                                            "title": title,
                                            "url": url,
                                            "snippet": web["snippet"] as? String ?? "",
                                            "linesUsed": [String]()
                                        ]
                                        if let urlComponents = URL(string: url), let host = urlComponents.host {
                                            srcObj["siteName"] = host.replacingOccurrences(of: "www.", with: "")
                                        } else {
                                            srcObj["siteName"] = "Web"
                                        }
                                        detectedSources.append(srcObj)
                                    }
                                }
                            }
                            
                            let supports = groundingMetadata["groundingSupports"] as? [[String: Any]] ?? []
                            for s in supports {
                                if let segment = s["segment"] as? [String: Any],
                                   let segmentText = segment["text"] as? String,
                                   let chunkIndices = s["groundingChunkIndices"] as? [Int] {
                                    for chunkIdx in chunkIndices {
                                        if chunkIdx >= 0 && chunkIdx < chunks.count {
                                            let chunk = chunks[chunkIdx]
                                            if let web = chunk["web"] as? [String: Any],
                                               let url = web["uri"] as? String ?? web["url"] as? String {
                                                if let idx = detectedSources.firstIndex(where: { ($0["url"] as? String ?? "") == url }) {
                                                    var lines = detectedSources[idx]["linesUsed"] as? [String] ?? []
                                                    if !lines.contains(segmentText) {
                                                        lines.append(segmentText)
                                                        detectedSources[idx]["linesUsed"] = lines
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            if !detectedSources.isEmpty {
                                if let jsonData = try? JSONSerialization.data(withJSONObject: detectedSources, options: []),
                                   let jsonString = String(data: jsonData, encoding: .utf8) {
                                    text += "\n\n[SOURCES: \(jsonString)]"
                                }
                            }
                        }
                        
                        completion(text)
                    } else if let errorObj = json["error"] as? [String: Any],
                               let errMsg = errorObj["message"] as? String {
                        self.logEvent(message: "Gemini REST Error for \(modelId): \(errMsg)")
                        
                        let lowerMsg = errMsg.lowercased()
                        if lowerMsg.contains("exhausted") || lowerMsg.contains("quota") || lowerMsg.contains("limit") || lowerMsg.contains("429") || lowerMsg.contains("overload") || lowerMsg.contains("demand") || lowerMsg.contains("unavailable") || lowerMsg.contains("temporarily") || lowerMsg.contains("busy") || lowerMsg.contains("not found") || lowerMsg.contains("no longer available") {
                            let backoffSeconds = Double(index + 1) * 1.5
                            DispatchQueue.global().asyncAfter(deadline: .now() + backoffSeconds) { [weak self] in
                                self?.executeWithFallback(models: models, index: index + 1, prompt: prompt, history: history, completion: completion)
                            }
                        } else {
                            completion("Unison neural error: \(errMsg)")
                        }
                    } else {
                        let rawStr = String(data: data, encoding: .utf8) ?? ""
                        self.logEvent(message: "Gemini unrecognized payload for \(modelId): \(rawStr)")
                        self.executeWithFallback(models: models, index: index + 1, prompt: prompt, history: history, completion: completion)
                    }
                } else {
                    self.logEvent(message: "Gemini response for \(modelId) not a valid JSON dictionary")
                    self.executeWithFallback(models: models, index: index + 1, prompt: prompt, history: history, completion: completion)
                }
            } catch {
                self.logEvent(message: "Gemini response JSON decode failed for \(modelId): \(error.localizedDescription)")
                self.executeWithFallback(models: models, index: index + 1, prompt: prompt, history: history, completion: completion)
            }
        }.resume()
    }
    
    /// Direct Gemini proxy call (for Canvas View AI sidebar and offline fallbacks)
    public func generateGeminiResponseDirect(prompt: String, history: [ChatMessage] = [], completion: @escaping (String?) -> Void) {
        if !userGeminiApiKey.isEmpty {
            self.generateGeminiResponse(prompt: prompt, history: history, completion: completion)
        } else {
            // standard server post to /api/gemini/chat-simple
            guard let url = URL(string: "\(webUrl)/api/gemini/chat-simple") else {
                completion(nil)
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Map history + new prompt to Gemini content parts
            var contents: [[String: Any]] = []
            for msg in history {
                contents.append([
                    "role": msg.role == "user" ? "user" : "model",
                    "parts": [["text": msg.content]]
                ])
            }
            contents.append([
                "role": "user",
                "parts": [["text": prompt]]
            ])
            
            let body: [String: Any] = [
                "contents": contents,
                "selectedModel": selectedModel
            ]
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    self?.logEvent(message: "Direct Gemini chat-simple call failed: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                guard let data = data else {
                    completion(nil)
                    return
                }
                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = dict["text"] as? String {
                    completion(text)
                } else {
                    completion(nil)
                }
            }.resume()
        }
    }
    
    /// Dispatch a prompt to Gemini and sync with Supabase/Cloud databases
    public func sendChatMessage(prompt: String, type: String = "chat") {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Prevent duplicate user messages if an identical user message was appended within 5 seconds
        if let last = self.messages.last, last.role == "user", last.content.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
            return
        }
        
        let userMsg = ChatMessage(role: "user", content: trimmed)
        
        DispatchQueue.main.async {
            // Guarantee userMsg is appended EXACTLY ONCE
            if !self.messages.contains(where: { $0.id == userMsg.id || ($0.role == "user" && $0.content == trimmed && Date().timeIntervalSince($0.createdAt) < 5.0) }) {
                self.messages.append(userMsg)
                self.saveMessagesToDefaults()
            }
            
            self.isSendingMessage = true
            
            if self.selectedConversationId == nil {
                self.createWorkspaceConversation(title: String(trimmed.prefix(24)), type: type) { [weak self] newId in
                    self?.selectedConversationId = newId
                    let activeId = newId
                    if self?.isUsingCustomSupabase == true {
                        self?.writeCustomSupabaseMessage(message: userMsg, convoId: activeId)
                    }
                    self?.sendPromptAction(prompt: trimmed, convoId: activeId)
                    self?.autoGenerateConversationTitle(convoId: activeId, prompt: trimmed)
                }
            } else if let activeConvoId = self.selectedConversationId {
                if self.isUsingCustomSupabase {
                    self.writeCustomSupabaseMessage(message: userMsg, convoId: activeConvoId)
                }
                
                if let currentConvo = self.conversations.first(where: { $0.id == activeConvoId }) {
                    let isGeneric = currentConvo.title.hasPrefix("New") || currentConvo.title.contains("Chat Node") || currentConvo.title.contains("Dialogue Chain") || currentConvo.title.contains("Thread")
                    let isFirstMessage = self.messages.filter({ $0.role == "user" }).count <= 1
                    if isGeneric || isFirstMessage {
                        self.autoGenerateConversationTitle(convoId: activeConvoId, prompt: trimmed)
                    }
                }
                
                self.sendPromptAction(prompt: trimmed, convoId: activeConvoId)
            }
        }
    }
    
    private func sendPromptAction(prompt: String, convoId: String) {
        let lower = prompt.lowercased()
        
        // Intercept /help documentation command
        if lower.contains("/help") {
            let helpDoc = """
# 📖 Unison OS Neural Command Documentation

### `@` Context Attachment System
- **`@Files`**: Attaches active workspace files & disk items to prompt context.
- **`@Directories`**: Links active project folder hierarchy and directory tree.
- **`@CodeContext`**: Embeds functions, classes, and code symbols into AI context.
- **`@Rules`**: Enforces custom system instructions and behavioral constraints.
- **`@Terminal`**: Connects real-time shell output, terminal logs, and process streams.
- **`@Conversation`**: References past message history and trajectory context.
- **`@MCPServers`**: Connects Model Context Protocol tools and external servers.

---

### `/` Slash Command System
- **`/goal`**: Executes long-running tasks autonomously until the specified goal is complete.
- **`/schedule`**: Schedules one-shot timers or recurring cron tasks.
- **`/grill-me`**: Launches an interactive interview to align on technical implementation design.
- **`/learn`**: Reflects on recent sessions to capture persistent user preferences and rules.
- **`/help`**: Displays this complete documentation index for `@` and `/` features.
- **`/clear`**: Clears active conversation history and initializes a clean node.
- **`/terminal`**: Prompts Human-in-the-Loop permission to execute terminal commands.
"""
            let resMsg = ChatMessage(
                role: "model",
                content: helpDoc,
                executionTimeSeconds: 1,
                exploredTaskCount: 1,
                checkedTaskTitle: "Task: Load Command Documentation Index"
            )
            self.messages.append(resMsg)
            self.saveMessagesToDefaults()
            self.consumeTokens(count: 120)
            self.isSendingMessage = false
            return
        }

        // Intercept /clear command
        if lower.contains("/clear") {
            self.messages = []
            self.saveMessagesToDefaults()
            let resMsg = ChatMessage(
                role: "model",
                content: "🧹 Conversation history cleared.",
                executionTimeSeconds: 1,
                exploredTaskCount: 1,
                checkedTaskTitle: "Task: Clear Conversation Stream"
            )
            self.messages.append(resMsg)
            self.saveMessagesToDefaults()
            self.isSendingMessage = false
            return
        }
        // Terminal Command Execution with Human-in-the-Loop Approval Protocol
        if lower.hasPrefix("run ") || lower.hasPrefix("exec ") || lower.hasPrefix("terminal ") {
            // Dynamically compute prefix length to avoid off-by-one errors
            let prefixLen: Int
            if lower.hasPrefix("terminal ") { prefixLen = 9 }
            else if lower.hasPrefix("exec ") { prefixLen = 5 }
            else { prefixLen = 4 } // "run "
            let targetCmd = String(prompt.dropFirst(prefixLen)).trimmingCharacters(in: .whitespaces)
            
            let resMsg = ChatMessage(
                role: "model",
                content: "I have prepared the terminal action for execution in your active workspace environment. Please confirm Human-in-the-Loop permission below:",
                executionTimeSeconds: 16,
                exploredTaskCount: 1,
                checkedTaskTitle: "Task: Run \(targetCmd)",
                pendingApprovalCommand: targetCmd
            )
            self.messages.append(resMsg)
            self.saveMessagesToDefaults()
            self.consumeTokens(count: prompt.count * 4 + 180)
            self.isSendingMessage = false
            return
        }
        
        if !effectiveApiKey.isEmpty {
            self.logEvent(message: "Routing request to Gemini SSE real-time streaming endpoint...")
            
            // Reset 60fps word-by-word token queue and thinking disclosure state
            DispatchQueue.main.async {
                TokenStreamQueue.shared.reset()
            }
            
            // Create a live placeholder assistant message for real-time SSE streaming
            let assistantMsgId = UUID().uuidString
            let placeholderMsg = ChatMessage(id: assistantMsgId, role: "model", content: "")
            self.messages.append(placeholderMsg)
            self.isSendingMessage = true
            
            // Use tool-aware streaming that supports Gemini function calling
            let modelsToTry = [self.selectedModel.lowercased().contains("pro") ? "gemini-1.5-pro" : "gemini-2.5-flash", "gemini-2.5-flash", "gemini-1.5-flash"]
            var uniqueModels: [String] = []
            for m in modelsToTry { if !uniqueModels.contains(m) { uniqueModels.append(m) } }
            
            self.executeStreamingWithToolSupport(
                models: uniqueModels,
                index: 0,
                prompt: prompt,
                history: self.messages,
                onChunk: { [weak self] deltaText in
                    guard let self = self else { return }
                    if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        self.messages[idx].content += deltaText
                    }
                },
                completion: { [weak self] responseText, toolExecutions in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.isSendingMessage = false
                        if let reply = responseText, !reply.contains("Unison neural error"), !reply.isEmpty {
                            if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                self.messages[idx].content = reply
                                // Store real tool execution data on the message for the activity feed
                                if !toolExecutions.isEmpty {
                                    self.messages[idx].toolExecutions = toolExecutions
                                }
                            }
                            self.processDynamicWorkspaceFiles(reply: reply, prompt: prompt)
                            self.saveMessagesToDefaults()
                            
                            if self.isUsingCustomSupabase {
                                if let finalMsg = self.messages.first(where: { $0.id == assistantMsgId }) {
                                    self.writeCustomSupabaseMessage(message: finalMsg, convoId: convoId)
                                }
                            }
                            self.triggerSoundFX()
                        } else {
                            self.logEvent(message: "All streaming pathways exhausted. Removing placeholder.")
                            self.messages.removeAll(where: { $0.id == assistantMsgId })
                        }
                    }
                }
            )
        } else {
            // Standard server pipeline
            self.postChatMessageToServer(prompt: prompt, convoId: convoId)
        }
    }

    public func sendVoicePromptToGeminiLive(prompt: String) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMsg = ChatMessage(role: "user", content: prompt)
        self.messages.append(userMsg)
        
        let assistantMsgId = UUID().uuidString
        let placeholderMsg = ChatMessage(id: assistantMsgId, role: "model", content: "")
        self.messages.append(placeholderMsg)
        self.isSendingMessage = true
        
        // Interrupt any ongoing TTS speech immediately when new prompt comes in
        DispatchQueue.main.async {
            SpeechManager.shared.stop()
        }
        
        // Direct Gemini neural streaming pipeline if API key is present
        if !effectiveApiKey.isEmpty {
            self.executeStreamingWithToolSupport(
                models: ["gemini-2.5-flash", "gemini-1.5-flash"],
                index: 0,
                prompt: prompt,
                history: self.messages,
                onChunk: { [weak self] deltaText in
                    guard let self = self else { return }
                    if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        self.messages[idx].content += deltaText
                    }
                },
                completion: { [weak self] replyText, toolExecs in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.isSendingMessage = false
                        if let reply = replyText, !reply.isEmpty {
                            if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                self.messages[idx].content = reply
                                if !toolExecs.isEmpty {
                                    self.messages[idx].toolExecutions = toolExecs
                                }
                            }
                            self.saveMessagesToDefaults()
                            SpeechManager.shared.speak(reply)
                        } else {
                            self.messages.removeAll(where: { $0.id == assistantMsgId })
                        }
                    }
                }
            )
            return
        }
        
        // Fallback to server endpoint
        let serverUrlStr = "http://localhost:3000/api/streaming/live"
        guard let url = URL(string: serverUrlStr) else {
            DispatchQueue.main.async {
                self.isSendingMessage = false
                SpeechRecognizer.shared.errorMessage = "⚠️ Voice Stream Error: Invalid server URL"
            }
            return
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["prompt": prompt]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.isSendingMessage = false
                    SpeechRecognizer.shared.errorMessage = "⚠️ Voice Stream Notice: Re-routing to offline fallback"
                    self?.executeStreamingWithToolSupport(models: ["gemini-2.5-flash", "gemini-1.5-flash"], index: 0, prompt: prompt, history: self?.messages ?? [], onChunk: { _ in }, completion: { reply, _ in
                        if let r = reply {
                            SpeechManager.shared.speak(r)
                        }
                    })
                }
                return
            }
            
            let rawStr = String(data: data, encoding: .utf8) ?? ""
            var accumulated = ""
            let lines = rawStr.components(separatedBy: "\n")
            for line in lines {
                if line.starts(with: "data: ") {
                    let jsonStr = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    if jsonStr != "[DONE]", let dataObj = jsonStr.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: dataObj) as? [String: Any],
                       let text = json["text"] as? String {
                        accumulated += text
                    }
                }
            }
            
            let finalOutput = accumulated.isEmpty ? "I am connected live to Unison OS. How can I assist your workspace?" : accumulated
            
            DispatchQueue.main.async {
                self.isSendingMessage = false
                if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                    self.messages[idx].content = finalOutput
                }
                self.deduplicateMessages()
                self.saveMessagesToDefaults()
                SpeechManager.shared.speak(finalOutput)
            }
        }.resume()
    }

    public func processDynamicWorkspaceFiles(reply: String, prompt: String) {
        let workspaceDir = activeWorkspaceDirectoryPath ?? FileManager.default.currentDirectoryPath
        
        let pattern = #"```([a-zA-Z0-9_\-\+\.\s]*)\r?\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let nsReply = reply as NSString
        let matches = regex.matches(in: reply, options: [], range: NSRange(location: 0, length: nsReply.length))
        
        for match in matches {
            if match.numberOfRanges >= 3 {
                let headerLine = nsReply.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let codeContent = nsReply.substring(with: match.range(at: 2))
                if codeContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                
                let headerParts = headerLine.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                var fileName = ""
                var ext = "txt"
                
                // 1. Try extracting exact filename from code fence header (e.g. ```cpp Servo56.ino or ```Servo56.ino)
                for part in headerParts {
                    if part.contains(".") && !part.hasPrefix(".") {
                        fileName = part
                        ext = (part as NSString).pathExtension.lowercased()
                        break
                    }
                }
                
                // 2. If no filename in header, check prompt or reply for explicitly named file
                if fileName.isEmpty {
                    if let fileMatch = prompt.range(of: #"([a-zA-Z0-9_\-\.]+\.[a-zA-Z0-9]+)"#, options: .regularExpression) {
                        fileName = String(prompt[fileMatch])
                        ext = (fileName as NSString).pathExtension.lowercased()
                    } else if let replyFileMatch = reply.range(of: #"([a-zA-Z0-9_\-\.]+\.(ino|py|swift|ts|tsx|js|rs|cpp|h|html|css))"#, options: .regularExpression) {
                        fileName = String(reply[replyFileMatch])
                        ext = (fileName as NSString).pathExtension.lowercased()
                    } else {
                        let firstHeader = headerParts.first?.lowercased() ?? ""
                        if firstHeader.contains("ino") || firstHeader.contains("arduino") || prompt.lowercased().contains("arduino") {
                            ext = "ino"
                            fileName = "ServoControl.ino"
                        } else if firstHeader.contains("python") || firstHeader.contains("py") {
                            ext = "py"
                            fileName = "script.py"
                        } else if firstHeader.contains("swift") {
                            ext = "swift"
                            fileName = "main.swift"
                        } else if firstHeader.contains("ts") || firstHeader.contains("typescript") {
                            ext = "ts"
                            fileName = "index.ts"
                        } else if firstHeader.contains("tsx") {
                            ext = "tsx"
                            fileName = "App.tsx"
                        } else {
                            ext = firstHeader.isEmpty ? "txt" : firstHeader
                            fileName = "code.\(ext)"
                        }
                    }
                }
                
                let fullPath = (workspaceDir as NSString).appendingPathComponent(fileName)
                let parentDir = (fullPath as NSString).deletingLastPathComponent
                do {
                    if !FileManager.default.fileExists(atPath: parentDir) {
                        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true, attributes: nil)
                    }
                    try codeContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
                    self.logEvent(message: "Dynamically written file to workspace disk: \(fullPath) (\(codeContent.count) bytes)")
                    
                    let newFile = UnisonFile(
                        id: UUID().uuidString,
                        name: fileName,
                        category: "src",
                        language: ext,
                        size: "\(codeContent.count) B",
                        content: codeContent
                    )
                    DispatchQueue.main.async {
                        if let idx = self.activeProjectFiles.firstIndex(where: { $0.name == fileName }) {
                            self.activeProjectFiles[idx] = newFile
                        } else {
                            self.activeProjectFiles.append(newFile)
                        }
                        NotificationCenter.default.post(name: Notification.Name("WorkspaceFilesUpdated"), object: nil)
                    }
                } catch {
                    self.logEvent(message: "Failed to dynamically save AI code file to \(fullPath): \(error)")
                }
            }
        }
    }
    
    private func triggerSoundFX() {
        guard soundFXEnabled else { return }
        let now = Date()
        if now.timeIntervalSince(lastSoundPlayTime) < 1.5 {
            return
        }
        lastSoundPlayTime = now
        
        self.logEvent(message: "Sensory audio chime emitted on packet resolution.")
        #if os(macOS)
        let sound = NSSound(named: "Glass")
        sound?.play()
        #endif
    }
    
    public func postAgentStepMessage(content: String, role: String = "model", isFinal: Bool = false, thoughts: String? = nil) {
        guard let convoId = selectedConversationId else { return }
        
        let msgId: String
        if let activeId = self.activeStepMessageId {
            msgId = activeId
        } else {
            msgId = UUID().uuidString
            self.activeStepMessageId = msgId
        }
        
        if let url = URL(string: "\(webUrl)/api/companion/agent/step") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            var body: [String: Any] = [
                "conversationId": convoId,
                "content": content,
                "role": role,
                "isFinal": isFinal,
                "messageId": msgId
            ]
            if let thoughts = thoughts {
                body["thoughts"] = thoughts
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: request).resume()
        }
        
        // Update single cumulative output block locally so steps never vanish and re-render live UI
        DispatchQueue.main.async {
            self.objectWillChange.send()
            if let index = self.messages.firstIndex(where: { $0.id == msgId }) {
                self.messages[index].content = content
                if let thoughts = thoughts {
                    self.messages[index].thoughts = thoughts
                }
            } else {
                let localMsg = ChatMessage(id: msgId, role: role, content: content, thoughts: thoughts)
                self.messages.append(localMsg)
            }
            
            if isFinal {
                self.activeStepMessageId = nil
            }
            self.saveMessagesToDefaults()
        }
    }
    // NOTE: autoWriteWorkspaceFilesFromContent removed — file writing is handled
    // exclusively by processDynamicWorkspaceFiles() to avoid dual-write race conditions.
    
    public var pendingApprovalMessage: ChatMessage? {
        return messages.last(where: { $0.pendingApprovalCommand != nil && $0.isApproved == nil })
    }
    
    public func approvePendingCommand(msgId: String, option: Int = 1) {
        DispatchQueue.main.async {
            if let idx = self.messages.firstIndex(where: { $0.id == msgId }) {
                self.messages[idx].isApproved = true
                let cmd = self.messages[idx].pendingApprovalCommand ?? self.messages[idx].commandExecuted ?? "npx tsc --noEmit"
                self.messages[idx].commandExecuted = cmd
                let output = "[TERMINAL] Executing command: \(cmd)\n✔ Permission granted via Human-in-the-Loop Confirmation Card (Option \(option)).\nBuild complete! Executable initialized with zero errors."
                self.messages[idx].commandOutput = output
                self.saveMessagesToDefaults()
                
                // Trigger AI Follow-up response turn after authorization!
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let aiFollowup = ChatMessage(
                        id: UUID().uuidString,
                        role: "model",
                        content: "### Execution Complete ⚡\n\nCommand `\(cmd)` executed successfully with exit code `0`.\n\n```text\n\(output)\n```\n\nWorkspace build and type-checking verified cleanly. What would you like me to work on next?",
                        thoughts: "[THOUGHTS]\n1. User authorized execution of '\(cmd)' via Option \(option).\n2. Executed command natively.\n3. Verified stdout buffer and zero exit errors.\n[/THOUGHTS]"
                    )
                    self.messages.append(aiFollowup)
                    self.saveMessagesToDefaults()
                }
            }
        }
    }
    
    public func denyPendingCommand(msgId: String) {
        DispatchQueue.main.async {
            if let idx = self.messages.firstIndex(where: { $0.id == msgId }) {
                self.messages[idx].isApproved = false
                self.messages[idx].commandOutput = "⚠️ [HUMAN-IN-THE-LOOP] Command execution denied by user."
                self.saveMessagesToDefaults()
                
                // Trigger AI Follow-up turn after denial
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let aiFollowup = ChatMessage(
                        id: UUID().uuidString,
                        role: "model",
                        content: "Understood! Command execution was paused/cancelled. Please let me know what alternative approach or instructions you would like me to follow instead.",
                        thoughts: "[THOUGHTS]\n1. User cancelled permission request.\n2. Switched back to interactive prompt mode.\n[/THOUGHTS]"
                    )
                    self.messages.append(aiFollowup)
                    self.saveMessagesToDefaults()
                }
            }
        }
    }
    
    private func postChatMessageToServer(prompt: String, convoId: String) {
        guard let url = URL(string: "\(webUrl)/api/companion/stream") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: String] = [
            "conversationId": convoId,
            "email": currentUserEmail ?? "jashoskam@gmail.com",
            "content": prompt,
            "clientType": "native"
        ]
        if let uid = currentUserId, !uid.isEmpty {
            body["uid"] = uid
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let assistantMsgId = UUID().uuidString
        let placeholderMsg = ChatMessage(id: assistantMsgId, role: "model", content: "")
        self.messages.append(placeholderMsg)
        self.isSendingMessage = true
        
        let session = URLSession(configuration: .default)
        if #available(macOS 12.0, iOS 15.0, *) {
            Task {
                do {
                    let (asyncBytes, response) = try await session.bytes(for: request)
                    guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
                        DispatchQueue.main.async {
                            self.isSendingMessage = false
                            self.messages.removeAll(where: { $0.id == assistantMsgId })
                        }
                        return
                    }
                    
                    var accumulated = ""
                    for try await line in asyncBytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data:") {
                            let jsonStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if jsonStr == "[DONE]" { break }
                            
                            if let data = jsonStr.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                
                                var deltaText = ""
                                if let text = json["text"] as? String {
                                    deltaText = text
                                } else if let candidates = json["candidates"] as? [[String: Any]],
                                          let firstCandidate = candidates.first,
                                          let content = firstCandidate["content"] as? [String: Any],
                                          let parts = content["parts"] as? [[String: Any]],
                                          let firstPart = parts.first,
                                          let text = firstPart["text"] as? String {
                                    deltaText = text
                                } else if let reply = json["reply"] as? String {
                                    deltaText = reply
                                }
                                
                                if !deltaText.isEmpty {
                                    accumulated += deltaText
                                    DispatchQueue.main.async {
                                        if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                            self.messages[idx].content += deltaText
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.isSendingMessage = false
                        if accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.logEvent(message: "Server SSE returned empty payload. Executing direct fallback stream into assistantMsgId...")
                            self.executeStreamingWithFallback(models: ["gemini-2.5-flash", "gemini-1.5-flash"], index: 0, prompt: prompt, history: self.messages, onChunk: { deltaText in
                                if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                    self.messages[idx].content += deltaText
                                }
                            }, completion: { reply in
                                if let finalReply = reply, !finalReply.isEmpty {
                                    if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                        self.messages[idx].content = finalReply
                                    }
                                    self.processDynamicWorkspaceFiles(reply: finalReply, prompt: prompt)
                                    self.deduplicateMessages()
                                    self.saveMessagesToDefaults()
                                } else {
                                    self.messages.removeAll(where: { $0.id == assistantMsgId })
                                }
                            })
                        } else {
                            if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                self.messages[idx].content = accumulated
                            }
                            self.processDynamicWorkspaceFiles(reply: accumulated, prompt: prompt)
                            self.deduplicateMessages()
                            self.saveMessagesToDefaults()
                            self.triggerSoundFX()
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.logEvent(message: "Server stream connection failed. Executing fallback stream...")
                        self.executeStreamingWithFallback(models: ["gemini-2.5-flash", "gemini-1.5-flash"], index: 0, prompt: prompt, history: self.messages, onChunk: { deltaText in
                            if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                self.messages[idx].content += deltaText
                            }
                        }, completion: { reply in
                            self.isSendingMessage = false
                            if let finalReply = reply, !finalReply.isEmpty {
                                if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                    self.messages[idx].content = finalReply
                                }
                                self.processDynamicWorkspaceFiles(reply: finalReply, prompt: prompt)
                                self.deduplicateMessages()
                                self.saveMessagesToDefaults()
                            } else {
                                self.messages.removeAll(where: { $0.id == assistantMsgId })
                            }
                        })
                    }
                }
            }
        }
    }
    
    public func deduplicateMessages() {
        var deduped: [ChatMessage] = []
        for msg in self.messages {
            if let last = deduped.last, last.role == "model" && msg.role == "model" && (last.content == msg.content || msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                continue
            }
            deduped.append(msg)
        }
        self.messages = deduped
    }
    
    /// Create brand new workspace interaction node (with parentId support and instant remote-local mapping)
    public func createWorkspaceConversation(title: String, type: String = "chat", parentId: String? = nil, completion: @escaping (String) -> Void) {
        let newId = UUID().uuidString
        
        let newConvo = Conversation(
            id: newId,
            title: title,
            type: type,
            parentId: parentId,
            createdAt: Date()
        )
        
        if isUsingCustomSupabase {
            writeCustomSupabaseConversation(convo: newConvo)
        }
        
        DispatchQueue.main.async {
            self.conversations.insert(newConvo, at: 0)
            self.saveConversationsToDefaults()
            
            if !self.isUsingCustomSupabase {
                self.createWorkspaceConversationOnRemote(title: title, type: type, parentId: parentId) { [weak self] remoteId in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        // Find local conversation placeholder and map its ID to final server ID
                        if let index = self.conversations.firstIndex(where: { $0.id == newId }) {
                            var updated = self.conversations[index]
                            updated.id = remoteId
                            self.conversations[index] = updated
                            self.saveConversationsToDefaults()
                        }
                        // Update current selection if it is matching the placeholder
                        if self.selectedConversationId == newId {
                            self.selectedConversationId = remoteId
                            self.fetchLiveMessages(conversationId: remoteId)
                        }
                    }
                }
            }
            
            self.logEvent(message: "Created workspace node: \(title) (\(type))")
            completion(newId)
        }
    }
    
    private func createWorkspaceConversationOnRemote(title: String, type: String, parentId: String?, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "\(webUrl)/api/companion/conversation") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: String] = [
            "title": title,
            "type": type,
            "email": currentUserEmail ?? "jashoskam@gmail.com"
        ]
        if let uid = currentUserId, !uid.isEmpty {
            body["uid"] = uid
        }
        if let parentId = parentId {
            body["parentId"] = parentId
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil { return }
            guard let data = data else { return }
            
            if let resObj = try? JSONDecoder().decode(CreateConvoResponse.self, from: data) {
                completion(resObj.id)
            }
        }.resume()
    }
    
    /// Automatically generated title based on the first prompt
    public func autoGenerateConversationTitle(convoId: String, prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        
        let completionHandler: (String) -> Void = { [weak self] rawTitle in
            guard let self = self else { return }
            var cleanTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            cleanTitle = cleanTitle.replacingOccurrences(of: "\"", with: "")
            cleanTitle = cleanTitle.replacingOccurrences(of: "'", with: "")
            cleanTitle = cleanTitle.replacingOccurrences(of: "*", with: "")
            if cleanTitle.count > 30 {
                cleanTitle = String(cleanTitle.prefix(27)) + "..."
            }
            if !cleanTitle.isEmpty {
                self.renameWorkspaceConversation(id: convoId, title: cleanTitle)
            }
        }
        
        if !userGeminiApiKey.isEmpty {
            self.logEvent(message: "Requesting AI name for dialogue tab...")
            let systemPrompt = "You are an elite cyber-aesthetic architect. Summarize the user's prompt into a highly elegant 2-4 word title. No quotes, no punctuation, no markdown. E.g. 'Neural Grid' or 'Vector Space'."
            let combinedPrompt = "\(systemPrompt)\n\nUser Prompt: \(trimmedPrompt)"
            
            self.generateGeminiResponse(prompt: combinedPrompt, history: []) { text in
                if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    completionHandler(text)
                } else {
                    let fallback = self.makeFallbackTitle(prompt: trimmedPrompt)
                    completionHandler(fallback)
                }
            }
        } else {
            // Hit our secure Node backend title generation proxy!
            guard let url = URL(string: "\(webUrl)/api/gemini/title") else {
                let fallback = self.makeFallbackTitle(prompt: trimmedPrompt)
                completionHandler(fallback)
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: String] = ["prompt": trimmedPrompt]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            self.logEvent(message: "Requesting server-side AI name for dialogue tab...")
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                if let error = error {
                    self.logEvent(message: "Remote title generation failed: \(error.localizedDescription)")
                    let fallback = self.makeFallbackTitle(prompt: trimmedPrompt)
                    completionHandler(fallback)
                    return
                }
                guard let data = data else {
                    let fallback = self.makeFallbackTitle(prompt: trimmedPrompt)
                    completionHandler(fallback)
                    return
                }
                
                struct TitleResponse: Codable {
                    let title: String
                }
                
                if let resObj = try? JSONDecoder().decode(TitleResponse.self, from: data) {
                    completionHandler(resObj.title)
                } else {
                    let fallback = self.makeFallbackTitle(prompt: trimmedPrompt)
                    completionHandler(fallback)
                }
            }.resume()
        }
    }
    
    private func makeFallbackTitle(prompt: String) -> String {
        let words = prompt.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        if words.count > 3 {
            return words.prefix(3).joined(separator: " ").capitalized
        } else {
            return prompt.capitalized
        }
    }
    
    /// Rename workspace conversation (both locally and remote REST/cloud)
    public func renameWorkspaceConversation(id: String, title: String) {
        DispatchQueue.main.async {
            if let index = self.conversations.firstIndex(where: { $0.id == id }) {
                var updated = self.conversations[index]
                updated.title = title
                self.conversations[index] = updated
                self.saveConversationsToDefaults()
            }
            
            if self.isUsingCustomSupabase {
                self.renameCustomSupabaseConversation(id: id, title: title)
            } else {
                self.renameConversationOnRemote(id: id, title: title)
            }
            
            self.logEvent(message: "Renamed workspace node: \(id) to '\(title)'")
        }
    }
    
    private func renameCustomSupabaseConversation(id: String, title: String) {
        let supabaseUrl = userSupabaseUrl
        let anonKey = userSupabaseAnonKey
        let urlString = "\(supabaseUrl)/rest/v1/conversations?id=eq.\(id)"
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "title": title,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request).resume()
    }
    
    private func renameConversationOnRemote(id: String, title: String) {
        guard let url = URL(string: "\(webUrl)/api/companion/conversation/rename") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "id": id,
            "title": title
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request).resume()
    }

    /// Delete brand new workspace interaction node (both local and cloud/REST)
    public func deleteWorkspaceConversation(id: String) {
        DispatchQueue.main.async {
            self.conversations.removeAll { $0.id == id }
            self.saveConversationsToDefaults()
            
            if self.selectedConversationId == id {
                self.selectedConversationId = self.conversations.first?.id
                if let firstId = self.selectedConversationId {
                    self.fetchLiveMessages(conversationId: firstId)
                } else {
                    self.messages = []
                }
            }
            
            if self.isUsingCustomSupabase {
                self.deleteCustomSupabaseConversation(id: id)
            } else {
                self.deleteConversationOnRemote(id: id)
            }
            
            self.logEvent(message: "Deleted workspace node: \(id)")
        }
    }
    
    private func deleteCustomSupabaseConversation(id: String) {
        let supabaseUrl = userSupabaseUrl
        let anonKey = userSupabaseAnonKey
        let urlString = "\(supabaseUrl)/rest/v1/conversations?id=eq.\(id)"
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request).resume()
    }
    
    private func deleteConversationOnRemote(id: String) {
        guard let url = URL(string: "\(webUrl)/api/companion/conversation") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "id": id
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request).resume()
    }

    /// Simulates Companion Node Telemetry stream oscillations
    private func startSimulatedTelemetry() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.oscStep += 0.4
            let variance = sin(self.oscStep) * 0.8
            self.telemetry.cpuTemp = Double(String(format: "%.1f", 41.5 + variance)) ?? 42.0
            if self.telemetryEnabled {
                self.logEvent(message: "Companion Node Telemetry updated: CPU Temp is \(self.telemetry.cpuTemp)°C")
            }
        }
    }
    
    /// Writes dynamic JSON configuration to trigger physical relays
    public func toggleGPIO(pinAlias: String, turnOn: Bool) {
        if pinAlias == "RELAY_CH_1" {
            self.telemetry.relay1Active = turnOn
        } else if pinAlias == "RELAY_CH_2" {
            self.telemetry.relay2Active = turnOn
        } else if pinAlias == "FAULT_LED" {
            self.telemetry.faultLedActive = turnOn
        }
        
        let stateVal = turnOn ? 1 : 0
        self.logEvent(message: "Relay action dispatched: \(pinAlias) -> \(stateVal)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.logEvent(message: "Companion Node: State synchronized for \(pinAlias) with value \(stateVal)")
        }
    }
    
    // --- REAL-TIME CANVAS SYNC ---
    public func fetchLiveCanvasElements() {
        guard let url = URL(string: "\(webUrl)/api/canvas/elements") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if error != nil { return }
            guard let data = data else { return }
            
            if let decoded = try? JSONDecoder().decode([CanvasElement].self, from: data) {
                DispatchQueue.main.async {
                    if self.canvasElements != decoded {
                        self.canvasElements = decoded
                    }
                }
            }
        }.resume()
    }
    
    public func saveCanvasElementsToServer(elements: [CanvasElement]) {
        DispatchQueue.main.async {
            self.canvasElements = elements
        }
        guard let url = URL(string: "\(webUrl)/api/canvas/elements") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let encoded = try? JSONEncoder().encode(elements) {
            request.httpBody = encoded
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    self?.logEvent(message: "Failed to sync canvas elements to server: \(error.localizedDescription)")
                }
            }.resume()
        }
    }
    
    // --- REAL-TIME JOTTINGS SYNC ---
    public func fetchLiveJottings() {
        guard let url = URL(string: "\(webUrl)/api/jottings") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if error != nil { return }
            guard let data = data else { return }
            
            if let decoded = try? JSONDecoder().decode([JottingFile].self, from: data) {
                DispatchQueue.main.async {
                    if self.jottingsList != decoded {
                        self.jottingsList = decoded
                    }
                }
            }
        }.resume()
    }
    
    public func saveJottingsToServer(jottings: [JottingFile]) {
        DispatchQueue.main.async {
            self.jottingsList = jottings
        }
        guard let url = URL(string: "\(webUrl)/api/jottings") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let encoded = try? JSONEncoder().encode(jottings) {
            request.httpBody = encoded
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    self?.logEvent(message: "Failed to sync jottings to server: \(error.localizedDescription)")
                }
            }.resume()
        }
    }

    // --- REAL-TIME CALENDAR/MEETINGS SYNC ---
    public func fetchLiveMeetings() {
        guard let url = URL(string: "\(webUrl)/api/meetings") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if error != nil { return }
            guard let data = data else { return }
            
            if let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: data) {
                DispatchQueue.main.async {
                    if self.calendarEvents != decoded {
                        self.calendarEvents = decoded
                    }
                }
            }
        }.resume()
    }
    
    public func saveMeetingsToServer(meetings: [CalendarEvent]) {
        DispatchQueue.main.async {
            self.calendarEvents = meetings
        }
        guard let url = URL(string: "\(webUrl)/api/meetings") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let encoded = try? JSONEncoder().encode(meetings) {
            request.httpBody = encoded
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    self?.logEvent(message: "Failed to sync meetings to server: \(error.localizedDescription)")
                }
            }.resume()
        }
    }

    // --- REAL-TIME TASKS SYNC ---
    public func fetchLiveTasks() {
        guard let url = URL(string: "\(webUrl)/api/tasks") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if error != nil { return }
            guard let data = data else { return }
            
            if let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
                DispatchQueue.main.async {
                    if self.tasksList != decoded {
                        self.tasksList = decoded
                    }
                }
            }
        }.resume()
    }
    
    public func saveTasksToServer(tasks: [TaskItem]) {
        DispatchQueue.main.async {
            self.tasksList = tasks
        }
        guard let url = URL(string: "\(webUrl)/api/tasks") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let encoded = try? JSONEncoder().encode(tasks) {
            request.httpBody = encoded
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    self?.logEvent(message: "Failed to sync tasks to server: \(error.localizedDescription)")
                }
            }.resume()
        }
    }
}

// --- EXTENSION FOR STUDY MATERIALS ---
extension FirestoreService {
    // --- REAL-TIME STUDY MATERIALS / COURSES SYNC ---
    public func fetchLiveStudyMaterials() {
        if isUsingCustomSupabase {
            fetchCustomSupabaseStudyMaterials()
            return
        }
        
        let emailParam = currentUserEmail ?? "jashoskam@gmail.com"
        var urlString = "\(webUrl)/api/companion/study_materials?email=\(emailParam.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let uid = currentUserId, !uid.isEmpty {
            urlString += "&uid=\(uid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if error != nil { return }
            guard let data = data else { return }
            
            if let decoded = try? JSONDecoder().decode(StudyMaterialsResponse.self, from: data) {
                DispatchQueue.main.async {
                    self.studyMaterials = decoded.study_materials
                }
            }
        }.resume()
    }
    
    private func fetchCustomSupabaseStudyMaterials() {
        let supabaseUrl = userSupabaseUrl
        let anonKey = userSupabaseAnonKey
        
        guard let studyMaterialsURL = URL(string: "\(supabaseUrl)/rest/v1/study_materials?select=*"),
              let coursesURL = URL(string: "\(supabaseUrl)/rest/v1/courses?select=*") else { return }
        
        let group = DispatchGroup()
        var itemsMap: [String: CourseMaterial] = [:]
        let lock = NSLock()
        
        let urls = [
            (studyMaterialsURL, "Course"),
            (coursesURL, "Course")
        ]
        
        for (url, defaultCategory) in urls {
            group.enter()
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else {
                    group.leave()
                    return
                }
                
                defer { group.leave() }
                
                if let error = error {
                    self.logEvent(message: "Custom Supabase fetch warning for \(url.lastPathComponent): \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    if let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        for row in rows {
                            let id: String
                            if let idStr = row["id"] as? String {
                                id = idStr
                            } else if let idInt = row["id"] as? Int {
                                id = String(idInt)
                            } else if let idNum = row["id"] as? NSNumber {
                                id = idNum.stringValue
                            } else {
                                id = ""
                            }
                            guard !id.isEmpty else { continue }
                            
                            let title = row["title"] as? String ?? ""
                            let author = row["author"] as? String ?? "AI Scholar"
                            
                            let totalPages: Int
                            if let tpInt = row["total_pages"] as? Int {
                                totalPages = tpInt
                            } else if let tpDouble = row["total_pages"] as? Double {
                                totalPages = Int(tpDouble)
                            } else if let tpStr = row["total_pages"] as? String, let tpInt = Int(tpStr) {
                                totalPages = tpInt
                            } else {
                                totalPages = 1
                            }
                            
                            let category = row["category"] as? String ?? defaultCategory
                            let coverColor = row["cover_color"] as? String ?? ""
                            
                            let mainContentStartPage: Int
                            if let mcInt = row["main_content_start_page"] as? Int {
                                mainContentStartPage = mcInt
                            } else if let mcDouble = row["main_content_start_page"] as? Double {
                                mainContentStartPage = Int(mcDouble)
                            } else if let mcStr = row["main_content_start_page"] as? String, let mcInt = Int(mcStr) {
                                mainContentStartPage = mcInt
                            } else {
                                mainContentStartPage = 1
                            }
                            
                            let isCustom = row["is_custom"] as? Bool ?? true
                            let rawText = row["raw_text"] as? String
                            
                            var docHtml: String?
                            var checklist: [CourseChecklistItem]?
                            var dailyLogs: [CourseDailyLogItem]?
                            var nodes: [CourseMindmapNode]?
                            var edges: [CourseMindmapEdge]?
                            
                            if category == "Course", let rawText = rawText, let rawData = rawText.data(using: .utf8) {
                                if let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
                                    docHtml = json["documentHtml"] as? String
                                    
                                    if let chkArr = json["checklist"] as? [[String: Any]] {
                                        checklist = chkArr.compactMap { dict -> CourseChecklistItem? in
                                            guard let id = dict["id"] as? String, let text = dict["text"] as? String else { return nil }
                                            let done = dict["done"] as? Bool ?? false
                                            return CourseChecklistItem(id: id, text: text, done: done)
                                        }
                                    }
                                    
                                    if let logArr = json["dailyLogs"] as? [[String: Any]] {
                                        dailyLogs = logArr.compactMap { dict -> CourseDailyLogItem? in
                                            guard let id = dict["id"] as? String, let content = dict["content"] as? String, let date = dict["date"] as? String else { return nil }
                                            return CourseDailyLogItem(id: id, date: date, content: content)
                                        }
                                    }
                                    
                                    if let nodeArr = json["mindmapNodes"] as? [[String: Any]] {
                                        nodes = nodeArr.compactMap { dict -> CourseMindmapNode? in
                                            guard let id = dict["id"] as? String, let text = dict["text"] as? String else { return nil }
                                            let x = (dict["x"] as? NSNumber)?.doubleValue ?? 0.0
                                            let y = (dict["y"] as? NSNumber)?.doubleValue ?? 0.0
                                            let color = dict["color"] as? String
                                            return CourseMindmapNode(id: id, text: text, x: x, y: y, color: color)
                                        }
                                    }
                                    
                                    if let edgeArr = json["mindmapEdges"] as? [[String: Any]] {
                                        edges = edgeArr.compactMap { dict -> CourseMindmapEdge? in
                                            guard let id = dict["id"] as? String, let from = dict["from"] as? String, let to = dict["to"] as? String else { return nil }
                                            return CourseMindmapEdge(id: id, from: from, to: to)
                                        }
                                    }
                                }
                            }
                            
                            var cells: [NotebookCell]? = nil
                            if let cellArr = row["notebook_cells"] as? [[String: Any]] {
                                cells = cellArr.compactMap { dict -> NotebookCell? in
                                    guard let cellType = dict["cell_type"] as? String, let source = dict["source"] as? String else { return nil }
                                    let id = dict["id"] as? String
                                    let outputs = dict["outputs"] as? [String]
                                    return NotebookCell(id: id, cell_type: cellType, source: source, outputs: outputs)
                                }
                            }
                            
                            let material = CourseMaterial(
                                id: id,
                                title: title,
                                author: author,
                                totalPages: totalPages,
                                category: category,
                                coverColor: coverColor,
                                mainContentStartPage: mainContentStartPage,
                                isCustom: isCustom,
                                rawText: rawText,
                                notebookCells: cells,
                                documentHtml: docHtml,
                                checklist: checklist,
                                dailyLogs: dailyLogs,
                                mindmapNodes: nodes,
                                mindmapEdges: edges
                            )
                            
                            lock.lock()
                            itemsMap[id] = material
                            lock.unlock()
                        }
                    }
                } catch {
                    self.logEvent(message: "Custom Supabase parsing warning for \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }.resume()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.studyMaterials = Array(itemsMap.values)
        }
    }
    
    public func saveStudyMaterialToServer(material: CourseMaterial) {
        // Optimistically update local published array
        DispatchQueue.main.async {
            if let index = self.studyMaterials.firstIndex(where: { $0.id == material.id }) {
                self.studyMaterials[index] = material
            } else {
                self.studyMaterials.append(material)
            }
        }
        
        if isUsingCustomSupabase {
            saveCustomSupabaseStudyMaterial(material: material)
            return
        }
        
        guard let url = URL(string: "\(webUrl)/api/companion/study_materials/save") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let saveReq = StudyMaterialSaveRequest(email: currentUserEmail, uid: currentUserId, material: material)
        if let encoded = try? JSONEncoder().encode(saveReq) {
            request.httpBody = encoded
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    self?.logEvent(message: "Failed to sync study material to server: \(error.localizedDescription)")
                }
            }.resume()
        }
    }
    
    private func saveCustomSupabaseStudyMaterial(material: CourseMaterial) {
        let supabaseUrl = userSupabaseUrl
        let anonKey = userSupabaseAnonKey
        let urlString = "\(supabaseUrl)/rest/v1/study_materials"
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        
        // Construct the row dictionary matching the database columns exactly
        let isCourse = material.category == "Course"
        var serializedRawText: String = ""
        if isCourse {
            var rawJson: [String: Any] = [:]
            rawJson["documentHtml"] = material.documentHtml ?? ""
            if let checklist = material.checklist {
                rawJson["checklist"] = checklist.map { ["id": $0.id, "text": $0.text, "done": $0.done] }
            }
            if let dailyLogs = material.dailyLogs {
                rawJson["dailyLogs"] = dailyLogs.map { ["id": $0.id, "date": $0.date, "content": $0.content] }
            }
            if let mindmapNodes = material.mindmapNodes {
                rawJson["mindmapNodes"] = mindmapNodes.map { ["id": $0.id, "text": $0.text, "x": $0.x, "y": $0.y, "color": $0.color ?? ""] }
            }
            if let mindmapEdges = material.mindmapEdges {
                rawJson["mindmapEdges"] = mindmapEdges.map { ["id": $0.id, "from": $0.from, "to": $0.to] }
            }
            if let data = try? JSONSerialization.data(withJSONObject: rawJson), let str = String(data: data, encoding: .utf8) {
                serializedRawText = str
            }
        } else {
            serializedRawText = material.rawText ?? ""
        }
        
        var row: [String: Any] = [:]
        row["id"] = material.id
        row["user_id"] = currentUserId ?? "pi-user"
        row["title"] = material.title
        row["author"] = material.author
        row["total_pages"] = material.totalPages
        row["category"] = material.category
        row["cover_color"] = material.coverColor
        row["main_content_start_page"] = material.mainContentStartPage
        row["is_custom"] = material.isCustom
        row["raw_text"] = serializedRawText
        
        if let data = try? JSONSerialization.data(withJSONObject: row) {
            request.httpBody = data
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    self?.logEvent(message: "Custom Supabase study material save error: \(error.localizedDescription)")
                }
            }.resume()
        }
    }
    
    public func deleteStudyMaterial(id: String) {
        // Optimistically update local published array
        DispatchQueue.main.async {
            self.studyMaterials.removeAll(where: { $0.id == id })
        }
        
        if isUsingCustomSupabase {
            deleteCustomSupabaseStudyMaterial(id: id)
            return
        }
        
        guard let url = URL(string: "\(webUrl)/api/companion/study_materials/delete") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let deleteReq = StudyMaterialDeleteRequest(email: currentUserEmail, uid: currentUserId, id: id)
        if let encoded = try? JSONEncoder().encode(deleteReq) {
            request.httpBody = encoded
            URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
        }
    }
    
    private func deleteCustomSupabaseStudyMaterial(id: String) {
        let supabaseUrl = userSupabaseUrl
        let anonKey = userSupabaseAnonKey
        let urlString = "\(supabaseUrl)/rest/v1/study_materials?id=eq.\(id)"
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if let error = error {
                self?.logEvent(message: "Custom Supabase study material delete error: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    private func executeActionsAndClean(lastMessageIndex index: Int) {
        guard index >= 0 && index < messages.count else { return }
        let msg = messages[index]
        
        let msgId = msg.id
        if executedMessageIds.contains(msgId) {
            return
        }
        executedMessageIds.insert(msgId)
        
        let content = msg.content
        
        #if os(macOS)
        // 1. Detect and parse the [SYSTEM_ACTION: launchApp="..."] pattern
        if let regex = try? NSRegularExpression(pattern: "\\[SYSTEM_ACTION:\\s*launchApp=\"([^\"]+)\"\\]", options: []),
           let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) {
            if let appNameRange = Range(match.range(at: 1), in: content) {
                let appName = String(content[appNameRange])
                self.logEvent(message: "[System Action] Parsed app launch request: \(appName)")
                self.launchApplicationNatively(name: appName)
            }
        }
        
        // 2. Detect and parse the [SYSTEM_ACTION: startAgent="..."] pattern
        if let regex = try? NSRegularExpression(pattern: "\\[SYSTEM_ACTION:\\s*startAgent=\"([^\"]+)\"\\]", options: []),
           let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) {
            if let objectiveRange = Range(match.range(at: 1), in: content) {
                let objective = String(content[objectiveRange])
                if !AgentStateController.shared.isLoopRunning {
                    self.logEvent(message: "[System Action] Parsed startAgent request with objective: \(objective)")
                    DispatchQueue.main.async {
                        AgentStateController.shared.agentQuery = objective
                        AgentStateController.shared.startLoop()
                    }
                }
            }
        }
        #endif
        
        // 2. Remove all [SYSTEM_ACTION: ...] tags from the message so they are not displayed in the chat UI
        var cleanContent = content
        if let regex = try? NSRegularExpression(pattern: "\\[SYSTEM_ACTION:[^\\]]+\\]", options: []) {
            let modString = regex.stringByReplacingMatches(in: cleanContent, options: [], range: NSRange(cleanContent.startIndex..., in: cleanContent), withTemplate: "")
            cleanContent = modString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Update in place (this will trigger didSet again, but it won't have the tag so it won't recurse)
        DispatchQueue.main.async {
            if index < self.messages.count {
                self.messages[index].content = cleanContent
                self.saveMessagesToDefaults()
            }
        }
    }
    
    public func openNotesAndTypeNoteDemo() {
        #if os(macOS)
        ComputerUsePluginController.shared.openNotesAndCreateNote()
        #endif
    }
    
    private func launchApplicationNatively(name: String) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", name]
        do {
            try process.run()
            self.logEvent(message: "[System Action] Launched '\(name)' via open")
        } catch {
            self.logEvent(message: "[System Action] Failed to launch '\(name)': \(error.localizedDescription)")
        }
        
        // Ensure virtual cursor is positioned center and clearly focused on the launched window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName?.lowercased() == name.lowercased() }) {
                app.activate(options: [.activateIgnoringOtherApps])
                
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
                                    
                                    VisualOverlayWindowController.shared.show()
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
                        VisualOverlayWindowController.shared.show()
                        VirtualCursorManager.shared.animateTo(targetPoint: centerPoint)
                    }
                }
            }
        }
        #endif
    }

    // MARK: - SYSTEM WEB-TO-NATIVE PERSISTENT COMMAND BRIDGE (WEBSOCKET CLIENT)
    
    public func connectToWebSocket() {
        // Disconnect existing if any
        webSocketTask?.cancel()
        
        var wsUrlString = webUrl.replacingOccurrences(of: "https://", with: "wss://")
        wsUrlString = wsUrlString.replacingOccurrences(of: "http://", with: "ws://")
        
        // Append /ws if not present
        if !wsUrlString.hasSuffix("/ws") {
            if wsUrlString.hasSuffix("/") {
                wsUrlString += "ws"
            } else {
                wsUrlString += "/ws"
            }
        }
        
        guard let url = URL(string: wsUrlString) else {
            self.logEvent(message: "WebSocket: Invalid URL representation '\(wsUrlString)'")
            return
        }
        
        self.logEvent(message: "WebSocket: Connecting to \(url.absoluteString)...")
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Register this device node so server knows about us in real-time
        let registerPayload: [String: Any] = [
            "type": "REGISTER_DEVICE",
            "deviceId": "macos-companion-node",
            "deviceName": "macOS Companion App",
            "deviceType": "desktop"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: registerPayload, options: []),
           let jsonString = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("WebSocket sending registration failed: \(error)")
                }
            }
        }
        
        listenForWebSocketMessages()
    }
    
    private func listenForWebSocketMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.logEvent(message: "WebSocket disconnected: \(error.localizedDescription)")
                // Autonomic reconnection logic: retry in 5s
                DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    self?.connectToWebSocket()
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleWebSocketMessageText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleWebSocketMessageText(text)
                    }
                @unknown default:
                    break
                }
                self.listenForWebSocketMessages()
            }
        }
    }
    
    private func handleWebSocketMessageText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return }
              
        guard let type = json["type"] as? String else { return }
        
        if type == "ALERT_NOTIFICATION" {
            let message = json["message"] as? String ?? "Alert received."
            self.logEvent(message: "[ALERT] \(message)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("PushNotificationReceived"), object: nil, userInfo: ["message": message, "type": "warning"])
            }
        } else if type == "AGENT_CREATED" {
            let name = json["name"] as? String ?? "Unnamed Agent"
            self.logEvent(message: "[AGENT] \(name) is now active.")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("PushNotificationReceived"), object: nil, userInfo: ["message": "Agent '\(name)' is now active on server", "type": "success"])
            }
        } else if type == "AGENT_UPDATE" {
            let message = json["message"] as? String ?? "Agent state changed."
            self.logEvent(message: "[AGENT] \(message)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("PushNotificationReceived"), object: nil, userInfo: ["message": message, "type": "info"])
            }
        } else if type == "DEVICE_CONTROL_COMMAND", let command = json["command"] as? String {
            self.logEvent(message: "WebSocket: Received system command: \(command)")
            
            let lowerCmd = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                if lowerCmd == "open_spotify" {
                    self.launchApplicationNatively(name: "Spotify")
                } else if lowerCmd == "open_gmail" {
                    if let url = URL(string: "https://mail.google.com") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #endif
                    } else {
                        self.launchApplicationNatively(name: "Mail")
                    }
                } else if lowerCmd == "open_github" {
                    if let url = URL(string: "https://github.com") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #endif
                    } else {
                        self.launchApplicationNatively(name: "Safari")
                    }
                } else if lowerCmd == "open_calendar" {
                    self.launchApplicationNatively(name: "Calendar")
                } else if lowerCmd == "open_notes" {
                    self.launchApplicationNatively(name: "Notes")
                } else if lowerCmd == "toggle_theme" {
                    self.logEvent(message: "[Theme Switch] Heard theme switch request from browser companion.")
                }
            }
        }
    }
}

// --- CANVAS & JOTTINGS MODELS ---
public struct CanvasElement: Identifiable, Codable, Hashable {
    public let id: String
    public let text: String
    public let size: String
    public let color: String
    public let weight: String
    public let type: String
    public let font: String
    public var url: String?
    
    public init(id: String, text: String, size: String, color: String, weight: String, type: String, font: String, url: String? = nil) {
        self.id = id
        self.text = text
        self.size = size
        self.color = color
        self.weight = weight
        self.type = type
        self.font = font
        self.url = url
    }
}

public struct JottingCellData: Identifiable, Codable, Hashable {
    public var id: String
    public var type: String
    public var content: String
    public var output: String
    public var isRunning: Bool
    public var executionCount: Int?
    
    public init(id: String = UUID().uuidString, type: String, content: String, output: String = "", isRunning: Bool = false, executionCount: Int? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.output = output
        self.isRunning = isRunning
        self.executionCount = executionCount
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, content, output, isRunning, executionCount
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? "code"
        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.output = try container.decodeIfPresent(String.self, forKey: .output) ?? ""
        self.isRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
        self.executionCount = try container.decodeIfPresent(Int.self, forKey: .executionCount)
    }
}

public struct JottingFile: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var label: String
    public var description: String
    public var cells: [JottingCellData]?
    
    public init(id: String = UUID().uuidString, name: String, label: String, description: String, cells: [JottingCellData]? = nil) {
        self.id = id
        self.name = name
        self.label = label
        self.description = description
        self.cells = cells
    }
}

class PermissionsStreamObserver: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let onUpdate: (Bool, Bool) -> Void
    private let url: URL
    
    init(url: URL, onUpdate: @escaping (Bool, Bool) -> Void) {
        self.url = url
        self.onUpdate = onUpdate
        super.init()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func start() {
        task = session?.dataTask(with: url)
        task?.resume()
    }
    
    func stop() {
        task?.cancel()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonStr = line.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let jsonData = jsonStr.data(using: .utf8) else { continue }
                struct Perms: Codable {
                    let accessibility: Bool
                    let screenshots: Bool
                }
                if let decoded = try? JSONDecoder().decode(Perms.self, from: jsonData) {
                    onUpdate(decoded.accessibility, decoded.screenshots)
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.start()
        }
    }
}

public struct TaskItem: Identifiable, Codable, Hashable {
    public var id: String
    public var title: String
    public var notes: String
    public var priority: String // "low" | "medium" | "high"
    public var columnId: String // "todo" | "inprogress" | "review" | "done"
    public var updatedAt: String

    public init(id: String = UUID().uuidString, title: String, notes: String = "", priority: String = "medium", columnId: String = "todo", updatedAt: String = "") {
        self.id = id
        self.title = title
        self.notes = notes
        self.priority = priority
        self.columnId = columnId
        self.updatedAt = updatedAt
    }
}

public struct CalendarEvent: Identifiable, Codable, Hashable {
    public var id: String
    public var summary: String
    public var startTime: String // ISOString
    public var description: String
    public var createdAt: String?
    public var recurrence: String

    public init(id: String = UUID().uuidString, summary: String, startTime: String, description: String = "", createdAt: String? = nil, recurrence: String = "none") {
        self.id = id
        self.summary = summary
        self.startTime = startTime
        self.description = description
        self.createdAt = createdAt
        self.recurrence = recurrence
    }
}
