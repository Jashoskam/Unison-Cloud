import SwiftUI
import Combine
import AVFoundation

#if canImport(MessageUI)
import MessageUI
#endif

// MARK: - Constants & Custom Palette
struct UnisonPalette {
    static let bgDark = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let consoleBg = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let consoleBorder = Color(white: 0.16)
    static let textMuted = Color(white: 0.60)
    static let textGolden = Color(red: 1.0, green: 0.70, blue: 0.0) // Orange-yellow for "Hey Unison"
    static let greenNeon = Color(red: 0.13, green: 0.85, blue: 0.45) // Glowing Green
    static let darkPillBg = Color(white: 0.10)
}

/// Vector drawing representing the signature cursive continuous string logo shown in image_2b1d9c.png
struct UnisonLoopLogo: View {
    var body: some View {
        ZStack {
            // Dark glowing outer frame
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black)
                .frame(width: 96, height: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                )
                .shadow(color: Color.blue.opacity(0.15), radius: 10, x: 0, y: 4)
            
            // White background canvas for the loop symbol
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .frame(width: 72, height: 72)
                .overlay(
                    // Detailed cursive unison ribbon/string
                    UnisonRibbonShape()
                        .stroke(Color.black, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                        .padding(14)
                )
        }
    }
}

/// Bezier path for the custom looped ribbon icon
struct UnisonRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Cursive double loop symbol
        path.move(to: CGPoint(x: w * 0.32, y: h * 0.28))
        
        // Left loop going down
        path.addCurve(to: CGPoint(x: w * 0.32, y: h * 0.72),
                      control1: CGPoint(x: w * 0.22, y: h * 0.28),
                      control2: CGPoint(x: w * 0.22, y: h * 0.72))
        
        // Connecting path crossing up to the right loop
        path.addCurve(to: CGPoint(x: w * 0.68, y: h * 0.28),
                      control1: CGPoint(x: w * 0.42, y: h * 0.72),
                      control2: CGPoint(x: w * 0.58, y: h * 0.28))
                      
        // Right loop going down and closing up
        path.addCurve(to: CGPoint(x: w * 0.68, y: h * 0.72),
                      control1: CGPoint(x: w * 0.78, y: h * 0.28),
                      control2: CGPoint(x: w * 0.78, y: h * 0.72))
                      
        // Swoosh to return/balance the drawing
        path.addCurve(to: CGPoint(x: w * 0.44, y: h * 0.56),
                      control1: CGPoint(x: w * 0.58, y: h * 0.72),
                      control2: CGPoint(x: w * 0.48, y: h * 0.64))
        
        return path
    }
}

class ChatViewModel: ObservableObject {
    @Published var promptText: String = ""
    @Published var tokenUsage: Int = 0
    @Published var cost: Double = 0.00
    @Published var selectedRouting: String = "Auto Routing"
    @Published var selectedModel: String = {
        FirestoreService.shared.selectedModel
    }() {
        didSet {
            FirestoreService.shared.selectedModel = selectedModel
        }
    }
    @Published var isMuted: Bool = true
    @Published var isRecording: Bool = false
    @Published var isHotwordModeEnabled: Bool = false
    @Published var autoSpeechUp: Bool = true
    @Published var attachedTools: Set<String> = []
    @Published var activeSegmentMode: String = "Chat"
    
    func toggleTool(_ tool: String) {
        if attachedTools.contains(tool) {
            attachedTools.remove(tool)
        } else {
            attachedTools.insert(tool)
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupSpeechSubscriptions()
    }
    
    private func setupSpeechSubscriptions() {
        // Stream active real-time transcript to prompt text
        SpeechRecognizer.shared.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self = self, self.isRecording else { return }
                if !text.isEmpty {
                    self.promptText = text
                }
            }
            .store(in: &cancellables)
            
        // Sync active speech recorder listening state
        SpeechRecognizer.shared.$isListening
            .receive(on: DispatchQueue.main)
            .sink { [weak self] listening in
                guard let self = self else { return }
                if self.isRecording != listening {
                    self.isRecording = listening
                }
            }
            .store(in: &cancellables)
            
        // Monitor background passive hotword listening state
        SpeechRecognizer.shared.$isHotwordActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                guard let self = self else { return }
                if self.isHotwordModeEnabled != active {
                    self.isHotwordModeEnabled = active
                }
            }
            .store(in: &cancellables)
            
        // Sync autoSpeechUp configuration
        SpeechRecognizer.shared.autoSpeechUpEnabled = self.autoSpeechUp
            
        // Setup wake word detected trigger callback
        SpeechRecognizer.shared.onHotwordDetected = { [weak self] in
            guard let self = self else { return }
            print("[ChatViewModel] Hotword DETECTED! Waking up active listen...")
            UnisonSoundEngine.shared.triggerSuccess()
            DispatchQueue.main.async {
                self.isRecording = true
                self.isHotwordModeEnabled = false
                SpeechRecognizer.shared.startListening()
            }
        }
        
        // Setup auto speech-up silence submit callback
        SpeechRecognizer.shared.onSilenceDetected = { [weak self] finalTranscript in
            guard let self = self else { return }
            print("[ChatViewModel] Silence detected! Performing auto-submit...")
            DispatchQueue.main.async {
                self.promptText = finalTranscript
                self.submitPrompt()
            }
        }
    }
    
    func submitPrompt() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        let db = FirestoreService.shared
        if db.selectedConversationId == nil {
            db.isNamingConversation = true
            let titlePrefix = String(text.prefix(28))
            db.newChatDraftTitle = titlePrefix
            db.createWorkspaceConversation(title: titlePrefix, type: "chat") { newId in
                db.selectedConversationId = newId
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    db.isNamingConversation = false
                }
            }
        }
        
        // Trigger computer use workflow if tool is attached or mentioned
        let activeTools = attachedTools
        let lowerText = text.lowercased()
        let isComputerUseRequested = self.activeSegmentMode == "Work" ||
            activeTools.contains("Computer Use") || 
            activeTools.contains("Apple Notes Operator") || 
            lowerText.contains("computer use") || 
            lowerText.contains("open notes") || 
            lowerText.contains("create note") ||
            lowerText.contains("click") ||
            lowerText.contains("open app") ||
            lowerText.contains("launch") ||
            lowerText.contains("operator") ||
            lowerText.contains("safari") ||
            lowerText.contains("youtube")
            
        if selectedModel.hasPrefix("Ollama") {
            FirestoreService.shared.sendOllamaChatMessage(prompt: text, modelName: selectedModel)
        } else if isComputerUseRequested {
            #if os(macOS)
            let userMsg = ChatMessage(role: "user", content: text)
            FirestoreService.shared.messages.append(userMsg)
            
            AgentStateController.shared.agentQuery = text
            AgentStateController.shared.startLoop()
            #endif
        } else {
            FirestoreService.shared.sendChatMessage(prompt: text)
        }
        
        // Simple calculations to emulate token count accumulation
        let calculatedTokens = text.count * 4
        tokenUsage += calculatedTokens
        cost += Double(calculatedTokens) * 0.00002
        promptText = ""
    }
    
    static func getLocalRoutingName(for prompt: String) -> String {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return "AUTO ROUTING" }
        
        let spotifyKeywords = ["play", "spotify", "track", "song", "music", "pause", "resume", "volume", "playlist", "queue"]
        if spotifyKeywords.contains(where: { text.contains($0) }) {
            return "SPOTIFY MEDIA SYSTEM"
        }

        let mailKeywords = ["email", "gmail", "inbox", "send to", "mail", "draft"]
        if mailKeywords.contains(where: { text.contains($0) }) {
            return "WORKSPACE MAIL CRAWLER"
        }

        let docKeywords = [ "spreadsheet", "sheet", "slides", "presentation", "deck", "powerpoint", "google doc"]
        if docKeywords.contains(where: { text.contains($0) }) {
            return "WORKSPACE DOC SYNCHRONIZER"
        }

        let codeKeywords = ["build", "create project", "develop", "code", "file", "index.html", "script", "function", "calculator", "applet"]
        if codeKeywords.contains(where: { text.contains($0) }) {
            return "CO-PILOT APPLICATION DEV"
        }

        let researchKeywords = ["research", "report", "deep dive", "analysis", "investigate", "whitepaper"]
        if researchKeywords.contains(where: { text.contains($0) }) {
            return "DEEP INTERNET RESEARCHER"
        }

        let searchKeywords = ["weather", "forecast", "news", "current status", "traffic", "price", "stock", "bitcoin", "today", "yesterday", "search", "google", "lookup", "what is", "who is", "how is"]
        if searchKeywords.contains(where: { text.contains($0) }) {
            return "GOOGLE SEARCH INDEXER"
        }

        let conversationKeywords = ["hi", "hello", "hey", "greetings", "how are you", "who are you", "your name", "thanks", "thank you", "yo", "sup"]
        if conversationKeywords.contains(where: { text.hasPrefix($0) || text == $0 }) || text.count < 15 {
            return "ZERO-AI DIRECT CHAT"
        }

        return "NEURAL ROUTING ROUTE"
    }
}

public struct ChatView: View {
    @ObservedObject var db = FirestoreService.shared
    @FocusState private var isInputFocused: Bool
    @StateObject private var vm = ChatViewModel()
    @State private var nebulaRotation: Double = 0.0
    @State private var isBlinking = false
    @State private var isUsageVisible = true
    @State private var isRightSidebarOpen = false
    @State private var activeSegmentMode: String = "Chat"
    @State private var isMentionDismissed: Bool = false
    @State private var isSlashDismissed: Bool = false
    
    // Multi-channel instant text messaging states
    @State private var showingSMSSheet = false
    @State private var smsRecipient = "+1 "
    @State private var smsBody = ""
    @State private var isSMSAlertShowing = false
    
    @Binding var isMobileSidebarOpen: Bool
    @Binding var isSidebarExpanded: Bool
    
    // Find activeMainConvo and childTabs mirroring Web UI behavior
    private var activeMainConvo: Conversation? {
        if let activeId = db.selectedConversationId,
           let activeConv = db.conversations.first(where: { $0.id == activeId }) {
            if activeConv.type == "main_convo" {
                return activeConv
            } else if let parentId = activeConv.parentId,
                      let parent = db.conversations.first(where: { $0.id == parentId }) {
                return parent
            }
        }
        return db.conversations.first(where: { $0.type == "main_convo" })
    }
    
    private var childTabs: [Conversation] {
        guard let mainConvo = activeMainConvo else { return [] }
        return db.conversations
            .filter { $0.parentId == mainConvo.id && ($0.type == "chat" || $0.type == "project") }
            .sorted(by: { $0.createdAt < $1.createdAt })
    }
    
    public init(isMobileSidebarOpen: Binding<Bool> = .constant(false), isSidebarExpanded: Binding<Bool> = .constant(true)) {
        self._isMobileSidebarOpen = isMobileSidebarOpen
        self._isSidebarExpanded = isSidebarExpanded
    }
    
    private func spawnNewConversation(type: String) {
        let parentId = (type == "main_convo") ? nil : activeMainConvo?.id
        let defaultTitle: String
        switch type {
        case "project":
            defaultTitle = "New Nested Repo"
        case "chat":
            defaultTitle = "New Nested Thread"
        default:
            defaultTitle = "New Chat Node"
        }
        
        db.createWorkspaceConversation(title: defaultTitle, type: type, parentId: parentId) { newId in
            db.selectedConversationId = newId
            db.messages = []
            db.fetchLiveMessages(conversationId: newId)
        }
    }
    
    public var body: some View {
        GeometryReader { geo in
            let isWidescreen = geo.size.width > 768
            let contentWidth = isWidescreen ? geo.size.width * 0.8 : geo.size.width
            
            ZStack {
                // Background dark layer matching the image canvas exactly
                UnisonPalette.bgDark
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top Bar Header (ChatGPT Style) - Spans full width
                    HStack(spacing: 12) {
                        if !isSidebarExpanded {
                            Button(action: {
                                withAnimation(.spring()) {
                                    isSidebarExpanded.toggle()
                                }
                            }) {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                db.createWorkspaceConversation(title: "New chat", type: "chat") { newId in
                                    db.selectedConversationId = newId
                                    db.messages = []
                                    db.fetchLiveMessages(conversationId: newId)
                                }
                            }) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Purple Get Plus button
                            Button(action: {}) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Get Plus")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(.purple)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.purple.opacity(0.15))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            // Purple Get Plus button when sidebar is open
                            Button(action: {}) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Get Plus")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(.purple)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.purple.opacity(0.15))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Spacer()
                        
                        // Centered Pill Segment Selector: Chat / Work
                        HStack(spacing: 0) {
                            Button(action: {
                                withAnimation(.spring()) {
                                    vm.activeSegmentMode = "Chat"
                                }
                            }) {
                                Text("Chat")
                                    .font(.system(size: 12, weight: vm.activeSegmentMode == "Chat" ? .bold : .medium))
                                    .foregroundColor(vm.activeSegmentMode == "Chat" ? .white : .white.opacity(0.5))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(vm.activeSegmentMode == "Chat" ? Color.white.opacity(0.12) : Color.clear)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                withAnimation(.spring()) {
                                    vm.activeSegmentMode = "Work"
                                    if !vm.attachedTools.contains("Computer Use") {
                                        vm.attachedTools.insert("Computer Use")
                                    }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "briefcase.fill")
                                        .font(.system(size: 10))
                                    Text("Work")
                                        .font(.system(size: 12, weight: vm.activeSegmentMode == "Work" ? .bold : .medium))
                                }
                                .foregroundColor(vm.activeSegmentMode == "Work" ? .white : .white.opacity(0.5))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(vm.activeSegmentMode == "Work" ? Color.cyan.opacity(0.2) : Color.clear)
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(2)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(14)
                        
                        Spacer()
                        
                        // Top Right buttons: Temporary Chat (dashed circle) with Computer Use test action & Sidebar right toggle
                        HStack(spacing: 8) {
                            Button(action: {
                                withAnimation(.spring()) {
                                    db.createWorkspaceConversation(title: "New chat", type: "chat") { newId in
                                        db.selectedConversationId = newId
                                        db.messages = []
                                        db.fetchLiveMessages(conversationId: newId)
                                    }
                                }
                            }) {
                                Image(systemName: "circle.dashed")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(6)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Start temporary unstored chat space")
                            
                            Button(action: {
                                withAnimation(.spring()) {
                                    isRightSidebarOpen.toggle()
                                }
                            }) {
                                Image(systemName: "sidebar.right")
                                    .font(.system(size: 13))
                                    .foregroundColor(isRightSidebarOpen ? .cyan : .white.opacity(0.7))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity)
                    
                    // Main Workspace Body Container
                    HStack(spacing: 0) {
                        // Main Chat column (Centered)
                        ZStack(alignment: .bottom) {
                            if db.messages.isEmpty {
                                VStack {
                                    Spacer()
                                    Text("What’s on the agenda today?")
                                        .font(.system(size: 32, weight: .medium))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                    Spacer()
                                }
                                .padding(.bottom, 100)
                            } else {
                                ScrollViewReader { proxy in
                                    ScrollView {
                                        VStack(alignment: .center, spacing: 16) {
                                            ForEach(db.messages) { msg in
                                                AnimatedMessageRow(msg: msg, contentWidth: min(geo.size.width * 0.85, 768)) { followUpQuestion in
                                                    vm.promptText = followUpQuestion
                                                    vm.submitPrompt()
                                                }
                                                .id(msg.id)
                                            }
                                            
                                            if db.isSendingMessage {
                                                let isLastUserMsg = db.messages.last?.role == "user"
                                                if isLastUserMsg {
                                                    DynamicThinkingBlockView(thoughts: "Analyzing prompt, scanning workspace files & generating code...", isStreaming: true)
                                                        .padding(.horizontal, 24)
                                                        .padding(.vertical, 8)
                                                }
                                            }
                                        }
                                        .frame(maxWidth: 768)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .padding(.bottom, 120) // Clearance for floating bottom input box
                                    }
                                    .onChange(of: db.messages.count) { _ in
                                        if let lastItem = db.messages.last {
                                            withAnimation {
                                                proxy.scrollTo(lastItem.id, anchor: .bottom)
                                            }
                                            if vm.isRecording, lastItem.role == "model" {
                                                SpeechManager.shared.speak(lastItem.content)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Bottom Console / Input Bar
                            VStack(spacing: 8) {
                                if ChatViewModel.getLocalRoutingName(for: vm.promptText) == "GOOGLE SEARCH INDEXER" {
                                    SearchCrawlerBar(prompt: vm.promptText) {
                                        withAnimation {
                                            vm.submitPrompt()
                                        }
                                    }
                                    .transition(.opacity)
                                }
                                
                                // Active Attached Tool Pills Tray
                                if !vm.attachedTools.isEmpty {
                                    HStack {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                ForEach(vm.attachedTools.sorted(), id: \.self) { tool in
                                                    HStack(spacing: 5) {
                                                        Image(systemName: iconForTool(tool))
                                                            .font(.system(size: 10, weight: .bold))
                                                        Text(tool)
                                                            .font(.system(size: 11, weight: .semibold))
                                                        Button(action: {
                                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                                _ = vm.attachedTools.remove(tool)
                                                            }
                                                        }) {
                                                            Image(systemName: "xmark")
                                                                .font(.system(size: 9, weight: .bold))
                                                                .foregroundColor(.white.opacity(0.6))
                                                        }
                                                        .buttonStyle(PlainButtonStyle())
                                                    }
                                                    .foregroundColor(Color(red: 0.0, green: 0.85, blue: 1.0))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(Color(red: 0.0, green: 0.85, blue: 1.0, opacity: 0.16))
                                                    .cornerRadius(12)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(Color(red: 0.0, green: 0.85, blue: 1.0), lineWidth: 1)
                                                            .opacity(vm.attachedTools.isEmpty ? 0.0 : 0.35)
                                                    )
                                                }
                                            }
                                            .padding(.horizontal, 4)
                                        }
                                        Spacer()
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                                
                                if !isMentionDismissed && vm.promptText.contains("@") {
                                    MentionAutocompleteMenu(filterText: vm.promptText) { tag in
                                        if let lastIndex = vm.promptText.lastIndex(of: "@") {
                                            vm.promptText = String(vm.promptText[..<lastIndex]) + tag + " "
                                        } else {
                                            vm.promptText += tag + " "
                                        }
                                        isMentionDismissed = true
                                    }
                                    .padding(.bottom, 8)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                                
                                if !isSlashDismissed && vm.promptText.hasPrefix("/") {
                                    SlashCommandAutocompleteMenu(filterText: vm.promptText) { cmd in
                                        vm.promptText = cmd + " "
                                        isSlashDismissed = true
                                    }
                                    .padding(.bottom, 8)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                                
                                if let pendingMsg = db.pendingApprovalMessage {
                                    HumanInTheLoopConfirmationCard(msg: pendingMsg)
                                        .padding(.bottom, 4)
                                        .transition(.scale(scale: 0.98).combined(with: .opacity))
                                } else if db.activeWorkspaceDirectoryPath != nil {
                                    // Project Mode Text Area (matching user screenshot)
                                    VStack(alignment: .leading, spacing: 0) {
                                        // Top Folder Header (matching screenshot: 📁 unison ⌵)
                                        HStack(spacing: 6) {
                                            Image(systemName: "folder")
                                                .foregroundColor(.white.opacity(0.6))
                                            Text((db.activeWorkspaceDirectoryPath! as NSString).lastPathComponent)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.white.opacity(0.85))
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white.opacity(0.4))
                                            Spacer()
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.bottom, 8)
                                        
                                        // Card Container (matching screenshot)
                                        VStack(alignment: .leading, spacing: 10) {
                                            // 1. Multiline Text Area Input (expands up to 4 lines!)
                                            TextField("Ask anything, @ to mention, / for actions", text: $vm.promptText, axis: .vertical)
                                                .focused($isInputFocused)
                                                .lineLimit(1...4)
                                                .font(.system(size: 14))
                                                .foregroundColor(.white)
                                                .textFieldStyle(PlainTextFieldStyle())
                                                .padding(.horizontal, 2)
                                                .padding(.top, 4)
                                                .onTapGesture {
                                                    isInputFocused = true
                                                    #if os(macOS)
                                                    NSApp.activate(ignoringOtherApps: true)
                                                    #endif
                                                }
                                            
                                            // 2. Middle Action Bar (+ Gemini 3.6 Flash High ⌵   🎙️ →)
                                            HStack(alignment: .center, spacing: 8) {
                                                // Plus attachment button
                                                Menu {
                                                    Button(action: { vm.toggleTool("Computer Use") }) {
                                                        Label("Computer Use (OS Control)", systemImage: "macwindow")
                                                    }
                                                    Button(action: { vm.toggleTool("Apple Notes Operator") }) {
                                                        Label("Apple Notes Operator", systemImage: "note.text")
                                                    }
                                                    Button(action: { vm.toggleTool("Vision Inspector") }) {
                                                        Label("Vision & Screen Capture", systemImage: "eye.fill")
                                                    }
                                                    Button(action: { vm.toggleTool("Web Search") }) {
                                                        Label("Web Search & Crawler", systemImage: "globe")
                                                    }
                                                    Button(action: { vm.toggleTool("Code Terminal") }) {
                                                        Label("Code & Shell Interpreter", systemImage: "terminal.fill")
                                                    }
                                                } label: {
                                                    Image(systemName: "plus")
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundColor(.white.opacity(0.6))
                                                }
                                                .menuStyle(BorderlessButtonMenuStyle())
                                                .help("Attach AI Tools")
                                                
                                                // Model Selector dropdown pill (matching screenshot: Gemini 3.6 Flash High ⌵)
                                                Menu {
                                                    Button(action: { vm.selectedModel = "Gemini 2.5 Flash" }) {
                                                        Text("Gemini 2.5 Flash")
                                                    }
                                                    Button(action: { vm.selectedModel = "Gemini 3.6 Flash High" }) {
                                                        Text("Gemini 3.6 Flash High")
                                                    }
                                                    Button(action: { vm.selectedModel = "Gemini Pro 1.5" }) {
                                                        Text("Gemini Pro 1.5")
                                                    }
                                                    Button(action: { vm.selectedModel = "Ollama: llama3" }) {
                                                        Text("Ollama: llama3 (Local)")
                                                    }
                                                    Button(action: { vm.selectedModel = "Ollama: qwen2.5-coder" }) {
                                                        Text("Ollama: qwen2.5-coder (Local)")
                                                    }
                                                    Button(action: { vm.selectedModel = "Ollama: mistral" }) {
                                                        Text("Ollama: mistral (Local)")
                                                    }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Text(vm.selectedModel.isEmpty ? "Gemini 3.6 Flash High" : vm.selectedModel)
                                                            .font(.system(size: 12, weight: .medium))
                                                            .foregroundColor(.white.opacity(0.75))
                                                        Image(systemName: "chevron.down")
                                                            .font(.system(size: 9, weight: .bold))
                                                            .foregroundColor(.white.opacity(0.4))
                                                    }
                                                }
                                                .menuStyle(BorderlessButtonMenuStyle())
                                                
                                                Spacer()
                                                
                                                // Mic button
                                                Button(action: {
                                                    if vm.isRecording {
                                                        vm.isRecording = false
                                                        SpeechRecognizer.shared.stopListening()
                                                    } else {
                                                        vm.isRecording = true
                                                        SpeechRecognizer.shared.startListening()
                                                    }
                                                }) {
                                                    Image(systemName: vm.isRecording ? "mic.fill" : "mic")
                                                        .font(.system(size: 13))
                                                        .foregroundColor(vm.isRecording ? .red : Color.white.opacity(0.5))
                                                        .frame(width: 24, height: 24)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                                
                                                // Send arrow button
                                                Button(action: {
                                                    if AgentStateController.shared.isLoopRunning {
                                                        AgentStateController.shared.stopLoop()
                                                    } else {
                                                        vm.submitPrompt()
                                                    }
                                                }) {
                                                    if AgentStateController.shared.isLoopRunning {
                                                        ZStack {
                                                            Circle()
                                                                .fill(Color.orange.opacity(0.9))
                                                                .frame(width: 26, height: 26)
                                                            ProgressView()
                                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                                .scaleEffect(0.5)
                                                        }
                                                    } else {
                                                        Image(systemName: "arrow.right")
                                                            .font(.system(size: 11, weight: .bold))
                                                            .foregroundColor(vm.promptText.isEmpty ? .white.opacity(0.3) : .white)
                                                            .frame(width: 26, height: 26)
                                                            .background(Color.white.opacity(vm.promptText.isEmpty ? 0.08 : 0.25))
                                                            .clipShape(Circle())
                                                    }
                                                }
                                                .disabled(vm.promptText.isEmpty && !AgentStateController.shared.isLoopRunning)
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                            
                                            Divider()
                                                .background(Color.white.opacity(0.06))
                                                .padding(.horizontal, -12)
                                            
                                            // 3. Bottom Row (matching screenshot: 💻 Local v    Main Agent v)
                                            HStack {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "laptopcomputer")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.white.opacity(0.5))
                                                    Text("Local")
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundColor(.white.opacity(0.65))
                                                    Image(systemName: "chevron.down")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .foregroundColor(.white.opacity(0.35))
                                                }
                                                
                                                Spacer()
                                                
                                                HStack(spacing: 4) {
                                                    Text("Main Agent")
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundColor(.white.opacity(0.65))
                                                    Image(systemName: "chevron.down")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .foregroundColor(.white.opacity(0.35))
                                                }
                                            }
                                            .padding(.top, 1)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.top, 12)
                                        .padding(.bottom, 10)
                                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            isInputFocused = true
                                            #if os(macOS)
                                            NSApp.activate(ignoringOtherApps: true)
                                            NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                                            #endif
                                        }
                                    }
                                } else {
                                    // Standard Mode Text Area (Clean floating card)
                                    HStack(alignment: .bottom, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 10) {
                                            TextField("Ask anything, @ to mention, / for actions", text: $vm.promptText, axis: .vertical)
                                                .focused($isInputFocused)
                                                .lineLimit(1...4)
                                                .font(.system(size: 14))
                                                .foregroundColor(.white)
                                                .textFieldStyle(PlainTextFieldStyle())
                                                .padding(.horizontal, 2)
                                                .padding(.top, 2)
                                                .onTapGesture {
                                                    isInputFocused = true
                                                    #if os(macOS)
                                                    NSApp.activate(ignoringOtherApps: true)
                                                    #endif
                                                }
                                            
                                            HStack(alignment: .center, spacing: 8) {
                                                Menu {
                                                    Button(action: { vm.toggleTool("Computer Use") }) { Label("Computer Use (OS Control)", systemImage: "macwindow") }
                                                    Button(action: { vm.toggleTool("Apple Notes Operator") }) { Label("Apple Notes Operator", systemImage: "note.text") }
                                                    Button(action: { vm.toggleTool("Vision Inspector") }) { Label("Vision & Screen Capture", systemImage: "eye.fill") }
                                                    Button(action: { vm.toggleTool("Web Search") }) { Label("Web Search & Crawler", systemImage: "globe") }
                                                    Button(action: { vm.toggleTool("Code Terminal") }) { Label("Code & Shell Interpreter", systemImage: "terminal.fill") }
                                                } label: {
                                                    Image(systemName: "plus")
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundColor(.white.opacity(0.6))
                                                }
                                                .menuStyle(BorderlessButtonMenuStyle())
                                                
                                                Menu {
                                                    Button(action: { vm.selectedModel = "Gemini 2.5 Flash" }) { Text("Gemini 2.5 Flash") }
                                                    Button(action: { vm.selectedModel = "Gemini 3.6 Flash High" }) { Text("Gemini 3.6 Flash High") }
                                                    Button(action: { vm.selectedModel = "Gemini Pro 1.5" }) { Text("Gemini Pro 1.5") }
                                                    Button(action: { vm.selectedModel = "Ollama: llama3" }) { Text("Ollama: llama3 (Local)") }
                                                    Button(action: { vm.selectedModel = "Ollama: qwen2.5-coder" }) { Text("Ollama: qwen2.5-coder (Local)") }
                                                    Button(action: { vm.selectedModel = "Ollama: mistral" }) { Text("Ollama: mistral (Local)") }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Text(vm.selectedModel.isEmpty ? "Gemini 3.6 Flash High" : vm.selectedModel)
                                                            .font(.system(size: 12, weight: .medium))
                                                            .foregroundColor(.white.opacity(0.75))
                                                        Image(systemName: "chevron.up")
                                                            .font(.system(size: 9, weight: .bold))
                                                            .foregroundColor(.white.opacity(0.4))
                                                    }
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.white.opacity(0.05))
                                                    .cornerRadius(6)
                                                }
                                                .menuStyle(BorderlessButtonMenuStyle())
                                                
                                                Spacer()
                                                
                                                Button(action: {
                                                    if vm.isRecording {
                                                        vm.isRecording = false
                                                        SpeechRecognizer.shared.stopListening()
                                                    } else {
                                                        vm.isRecording = true
                                                        SpeechRecognizer.shared.startListening()
                                                    }
                                                }) {
                                                    Image(systemName: vm.isRecording ? "mic.fill" : "mic")
                                                        .font(.system(size: 13))
                                                        .foregroundColor(vm.isRecording ? .red : Color.white.opacity(0.5))
                                                        .frame(width: 26, height: 26)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                                
                                                Button(action: {
                                                    if AgentStateController.shared.isLoopRunning {
                                                        AgentStateController.shared.stopLoop()
                                                    } else {
                                                        vm.submitPrompt()
                                                    }
                                                }) {
                                                    if AgentStateController.shared.isLoopRunning {
                                                        ZStack {
                                                            Circle().fill(Color.orange.opacity(0.9)).frame(width: 28, height: 28)
                                                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.6)
                                                        }
                                                    } else {
                                                        Image(systemName: "arrow.right")
                                                            .font(.system(size: 12, weight: .bold))
                                                            .foregroundColor(vm.promptText.isEmpty ? .white.opacity(0.3) : .white)
                                                            .frame(width: 28, height: 28)
                                                            .background(Color.white.opacity(vm.promptText.isEmpty ? 0.08 : 0.25))
                                                            .clipShape(Circle())
                                                    }
                                                }
                                                .disabled(vm.promptText.isEmpty && !AgentStateController.shared.isLoopRunning)
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color(red: 0.12, green: 0.12, blue: 0.13))
                                    .cornerRadius(18)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 4)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        isInputFocused = true
                                        #if os(macOS)
                                        NSApp.activate(ignoringOtherApps: true)
                                        #endif
                                    }
                                }
                            }
                            .frame(maxWidth: 768)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .onChange(of: vm.promptText) { newText in
                                if !newText.contains("@") {
                                    isMentionDismissed = false
                                }
                                if !newText.hasPrefix("/") {
                                    isSlashDismissed = false
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        if isRightSidebarOpen {
                            operatorCompanionPanel
                                .transition(.move(edge: .trailing))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $showingSMSSheet) {
                    SMSComposerSheet(recipient: $smsRecipient, body: $smsBody)
                        .preferredColorScheme(.dark)
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isRightSidebarOpen)
            }
        }
    }

    private func triggerComputerUsePerformanceTest() {
        #if os(macOS)
        ComputerUsePluginController.shared.openNotesAndCreateNote()
        #endif
    }

    private func iconForTool(_ tool: String) -> String {
        switch tool {
        case "Computer Use": return "macwindow"
        case "Apple Notes Operator": return "note.text"
        case "Vision Inspector": return "eye.fill"
        case "Web Search": return "globe"
        case "Code Terminal": return "terminal.fill"
        default: return "wrench.fill"
        }
    }

    @ViewBuilder
    private var operatorCompanionPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "location.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.cyan)
                    .rotationEffect(.init(degrees: -45))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Computer Use")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text(AgentStateController.shared.isLoopRunning ? "Operator Active" : "Operator Inactive")
                        .font(.system(size: 10))
                        .foregroundColor(AgentStateController.shared.isLoopRunning ? .green : .gray)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring()) {
                        isRightSidebarOpen = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.02))
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            ScrollView {
                VStack(spacing: 20) {
                    // Mini Screen Canvas Mockup
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Window Monitor")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 4)
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.6))
                                .frame(height: 160)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            
                            // Target App Frame indicator
                            if let targetApp = VirtualCursorManager.shared.selectedTargetApp {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.cyan.opacity(0.3), lineWidth: 1.5)
                                    .background(Color.cyan.opacity(0.03))
                                    .frame(width: 180, height: 100)
                                    .overlay(
                                        VStack {
                                            HStack {
                                                Image(systemName: "macwindow")
                                                    .font(.system(size: 9))
                                                Text(targetApp.name)
                                                    .font(.system(size: 9, weight: .bold))
                                                Spacer()
                                                Circle()
                                                    .fill(Color.cyan)
                                                    .frame(width: 4, height: 4)
                                            }
                                            .foregroundColor(.cyan)
                                            .padding(6)
                                            Spacer()
                                        }
                                    )
                            } else {
                                Text("No Target App Connected")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            
                            // Virtual Cursor indicator in monitor
                            Circle()
                                .fill(Color.pink)
                                .frame(width: 8, height: 8)
                                .shadow(color: .pink.opacity(0.6), radius: 4)
                                .offset(x: AgentStateController.shared.isLoopRunning ? CGFloat.random(in: -40...40) : 0,
                                        y: AgentStateController.shared.isLoopRunning ? CGFloat.random(in: -30...30) : 0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: AgentStateController.shared.isLoopRunning)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Selected App Dropdown Selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Application")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 4)
                        
                        Menu {
                            Button("Disconnect App") {
                                VirtualCursorManager.shared.selectedTargetApp = nil
                            }
                            
                            ForEach(VirtualCursorManager.getRunningApps()) { app in
                                Button(app.name) {
                                    VirtualCursorManager.shared.selectedTargetApp = app
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: VirtualCursorManager.shared.selectedTargetApp != nil ? "macwindow" : "rectangle.dashed")
                                    .foregroundColor(.white.opacity(0.7))
                                Text(VirtualCursorManager.shared.selectedTargetApp?.name ?? "Select Active Application...")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    
                    // Controls Box
                    VStack(spacing: 12) {
                        Button(action: {
                            if AgentStateController.shared.isLoopRunning {
                                AgentStateController.shared.stopLoop()
                            } else {
                                AgentStateController.shared.startLoop()
                            }
                        }) {
                            HStack {
                                Spacer()
                                Image(systemName: AgentStateController.shared.isLoopRunning ? "pause.fill" : "play.fill")
                                Text(AgentStateController.shared.isLoopRunning ? "PAUSE OPERATOR" : "START OPERATOR")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.0)
                                Spacer()
                            }
                            .foregroundColor(AgentStateController.shared.isLoopRunning ? .black : .white)
                            .padding(.vertical, 10)
                            .background(AgentStateController.shared.isLoopRunning ? Color.white : Color.cyan.opacity(0.8))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        if AgentStateController.shared.isLoopRunning {
                            Button(action: {
                                AgentStateController.shared.stopLoop()
                            }) {
                                HStack {
                                    Spacer()
                                    Image(systemName: "xmark.circle.fill")
                                    Text("TERMINATE LOOP")
                                        .font(.system(size: 11, weight: .bold))
                                        .tracking(1.0)
                                    Spacer()
                                }
                                .foregroundColor(.red)
                                .padding(.vertical, 10)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Feed list (Action history logs)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Action Telemetry Stream")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 4)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            if AgentStateController.shared.recentActions.isEmpty {
                                Text("No commands logged. Start loop to track actions.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.3))
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(Array(AgentStateController.shared.recentActions.enumerated()), id: \.offset) { _, action in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(Color.cyan.opacity(0.8))
                                            .frame(width: 5, height: 5)
                                            .offset(y: 5)
                                        
                                        Text(action)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.8))
                                            .lineSpacing(4)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 20)
            }
        }
        .frame(width: 320)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
    }
    
    // Refactored sub-view to speed up type-checking
    private var tokenTrackerView: some View {
        let usage = Text("\(vm.tokenUsage)")
            .foregroundColor(.white)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
        
        let costText = Text(String(format: "$%.5f", vm.cost))
            .foregroundColor(UnisonPalette.greenNeon)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
        
        return HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 11))
                .foregroundColor(UnisonPalette.textMuted)
            
            Text("USAGE: ")
                .foregroundColor(UnisonPalette.textMuted)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            + usage
            + Text(" tokens")
                .foregroundColor(UnisonPalette.textMuted)
                .font(.system(size: 10, design: .monospaced))
            + Text("  |  ")
                .foregroundColor(Color.white.opacity(0.15))
            + costText
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Shimmer Animation Effects
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    let duration: Double
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.08),
                            .clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .scaleEffect(1.6)
                    .offset(x: -geo.size.width + (geo.size.width * 2 * phase))
                    .onAppear {
                        withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
                .mask(content)
            )
    }
}

extension View {
    func shimmer(duration: Double = 1.4) -> some View {
        modifier(ShimmerModifier(duration: duration))
    }
}

// MARK: - Animated Message Row for Fluid Fade-In
struct AnimatedMessageRow: View {
    @ObservedObject var db = FirestoreService.shared
    let msg: ChatMessage
    let contentWidth: CGFloat
    var onSelectFollowUp: ((String) -> Void)? = nil
    @State private var opacity: Double = 0.0
    @State private var offsetY: CGFloat = 8.0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if msg.role == "user" {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(msg.content)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.12))
                        .cornerRadius(18)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: contentWidth * 0.75, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(db.selectedModel.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .tracking(1.5)
                    }
                    
                    let isCurrentMessageStreaming = db.isSendingMessage && msg.id == db.messages.last?.id
                    if msg.commandExecuted != nil || msg.pendingApprovalCommand != nil || msg.executionTimeSeconds != nil || msg.checkedTaskTitle != nil {
                        DynamicThoughtTrajectoryView(msg: msg)
                    }
                    FormattedResponseView(text: msg.content, thoughts: msg.thoughts, isStreaming: isCurrentMessageStreaming, toolExecutions: msg.toolExecutions, onSelectFollowUp: onSelectFollowUp)
                        .padding(.horizontal, 0)
                        .padding(.vertical, 4)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .textSelection(.enabled)
        .opacity(opacity)
        .offset(y: offsetY)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                opacity = 1.0
                offsetY = 0.0
            }
        }
    }
}

// MARK: - Thinking & Auto Routing Process View
struct ToolMeta {
    let name: String
    let color: Color
    let iconName: String
}

// MARK: - Routing Flow Animation View
struct RoutingFlowView: View {
    let routeName: String
    let isStreaming: Bool
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var dotPos: CGFloat = 0.0
    
    let timer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 8) {
            // Node 1: Input Prompt Source
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Circle()
                        .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                        .frame(width: 32, height: 32)
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                }
                Text("PROMPT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue.opacity(0.7))
            }
            .frame(width: 50)
            
            // Channel 1: Decoding flow path
            VStack(spacing: 2) {
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                    
                    // Animated packet dot
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 4, height: 4)
                        .offset(x: -16 + (dotPos * 32))
                }
                Text("DECODE")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.5))
            }
            
            // Node 2: Intelligent Core Router
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Circle()
                        .stroke(Color.purple.opacity(0.35), lineWidth: 1)
                        .frame(width: 36, height: 36)
                        .scaleEffect(isStreaming ? pulseScale : 1.0)
                        .opacity(isStreaming ? (1.5 - pulseScale) : 1.0)
                    Image(systemName: "cpu")
                        .font(.system(size: 13))
                        .foregroundColor(.purple)
                }
                Text("ROUTER")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.purple.opacity(0.7))
            }
            .frame(width: 50)
            
            // Channel 2: Dynamic Routing direction
            let meta = getToolMeta(for: routeName)
            VStack(spacing: 2) {
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                    
                    // Animated packet dot
                    Circle()
                        .fill(meta.color)
                        .frame(width: 4, height: 4)
                        .offset(x: -16 + (dotPos * 32))
                }
                Text("ROUTE")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundColor(meta.color.opacity(0.5))
            }
            
            // Node 3: Target System Target Node
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(meta.color.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Circle()
                        .stroke(meta.color.opacity(0.35), lineWidth: 1)
                        .frame(width: 32, height: 32)
                    Image(systemName: meta.iconName)
                        .font(.system(size: 11))
                        .foregroundColor(meta.color)
                }
                Text(meta.name)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(meta.color.opacity(0.7))
            }
            .frame(width: 65)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.02))
        .cornerRadius(10)
        .onReceive(timer) { _ in
            if isStreaming {
                withAnimation(.linear(duration: 0.03)) {
                    dotPos += 0.03
                    if dotPos > 1.0 {
                        dotPos = 0.0
                    }
                    pulseScale += 0.015
                    if pulseScale > 1.4 {
                        pulseScale = 1.0
                    }
                }
            }
        }
    }
    
    private func getToolMeta(for toolName: String) -> ToolMeta {
        switch toolName {
        case "SPOTIFY MEDIA SYSTEM":
            return ToolMeta(name: "SPOTIFY", color: .green, iconName: "music.note")
        case "WORKSPACE MAIL CRAWLER":
            return ToolMeta(name: "MAIL", color: .red, iconName: "envelope.fill")
        case "WORKSPACE DOC SYNCHRONIZER":
            return ToolMeta(name: "DOCS", color: .cyan, iconName: "doc.text.fill")
        case "CO-PILOT APPLICATION DEV":
            return ToolMeta(name: "CO-PILOT", color: .orange, iconName: "chevron.left.slash.chevron.right")
        case "DEEP INTERNET RESEARCHER":
            return ToolMeta(name: "DEEP_RES", color: .pink, iconName: "doc.text.magnifyingglass")
        case "GOOGLE SEARCH INDEXER":
            return ToolMeta(name: "SEARCH", color: .blue, iconName: "globe")
        case "ZERO-AI DIRECT CHAT":
            return ToolMeta(name: "DIRECT", color: .purple, iconName: "message.fill")
        default:
            return ToolMeta(name: "CORE_AI", color: .indigo, iconName: "cpu")
        }
    }
}

// MARK: - Search Crawler & Local Detect Views
struct SearchCrawlerBar: View {
    let prompt: String
    let onInstantRoute: () -> Void
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Text("GOOGLE SEARCH CRAWLER")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1.0))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                
                Text("|")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.15))
                    .fixedSize(horizontal: true, vertical: false)
                
                let displayPrompt = prompt.count > 32 ? String(prompt.prefix(32)) + "..." : prompt
                Text("Instant live index lookup request: \"\(displayPrompt)\"")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .layoutPriority(1)
            
            Spacer()
            
            Button(action: onInstantRoute) {
                Text("INSTANT ROUTE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color(red: 0.05, green: 0.04, blue: 0.09)
                .opacity(0.85)
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 0.15, green: 0.12, blue: 0.3).opacity(0.4), lineWidth: 1.5)
        )
    }
}

struct LocalDetectPill: View {
    let routeName: String
    @State private var pulseScale: CGFloat = 1.0
    @State private var opacity: Double = 0.8
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white.opacity(0.6)) // Monochrome indicator dot
                .frame(width: 6, height: 6)
                .scaleEffect(pulseScale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        pulseScale = 1.6
                        opacity = 0.3
                    }
                }
            
            Text("LOCAL DETECT: \(routeName)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color.white.opacity(0.04)
        )
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Voice Speech Manager for Gemini Live Audio Feedback
@MainActor
public final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    public static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()
    
    public var isSpeaking: Bool { synthesizer.isSpeaking }
    
    private override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    public func speak(_ text: String) {
        stop()
        let cleanText = text.replacingOccurrences(of: "*", with: "")
                            .replacingOccurrences(of: "`", with: "")
                            .replacingOccurrences(of: "#", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        
        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        
        // Select highest quality neural/enhanced voice if available
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()
        if let highQualityVoice = availableVoices.first(where: { $0.language.contains("en") && ($0.quality == .enhanced || $0.quality == .premium) }) {
            utterance.voice = highQualityVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        
        synthesizer.speak(utterance)
    }
    
    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}

#if os(iOS) && canImport(MessageUI)
// MARK: - Native iOS SMS Message Dispatch Bridge
struct SMSComposeView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    let recipient: String
    let body: String
    
    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var parent: SMSComposeView
        init(_ parent: SMSComposeView) { self.parent = parent }
        
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) {
                self.parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [recipient]
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
}
#endif

// MARK: - Decoupled Energy Orb Computations (Screenshot-Matched Grained Fluid Celestial Orb)
public struct OrbContentView: View {
    let time: Double
    let isSendingMessage: Bool
    let isRecording: Bool
    var audioLevel: Float = 0.0
    var size: CGFloat = 160.0
    
    public init(time: Double, isSendingMessage: Bool, isRecording: Bool, audioLevel: Float = 0.0, size: CGFloat = 160.0) {
        self.time = time
        self.isSendingMessage = isSendingMessage
        self.isRecording = isRecording
        self.audioLevel = audioLevel
        self.size = size
    }
    
    public var body: some View {
        let speed: Double = isSendingMessage ? 2.8 : (isRecording ? 1.8 + Double(audioLevel) * 1.5 : 0.8)
        let t = time * speed
        
        let baseScale: CGFloat = isSendingMessage ? 1.08 : (isRecording ? 1.15 + CGFloat(audioLevel) * 0.35 : 1.0)
        let waveYOffset = CGFloat(sin(t * 1.5)) * (size * 0.07)
        let waveRotate = Angle(degrees: sin(t * 0.8) * 8.0)
        
        return ZStack {
            // 1. Soft Outer Ice-Cyan & Deep Indigo Aura Bloom
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.70, green: 0.94, blue: 1.0).opacity(0.45 + sin(t * 2.0) * 0.15),
                            Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.25),
                            Color(red: 0.4, green: 0.1, blue: 0.9).opacity(0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.05,
                        endRadius: size * 0.75
                    )
                )
                .frame(width: size * 1.45, height: size * 1.45)
                .scaleEffect(baseScale * 1.15)
            
            // 2. Base Sphere Circle Mask
            ZStack {
                // Background Base: Deep Ocean Blue & Violet Gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.88, green: 0.97, blue: 1.0),
                        Color(red: 0.35, green: 0.78, blue: 1.0),
                        Color(red: 0.05, green: 0.45, blue: 0.98),
                        Color(red: 0.01, green: 0.25, blue: 0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // 3. Multi-Pass Fluid Blue Liquid Plasma Wave Layers
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.65, green: 0.92, blue: 1.0).opacity(0.95),
                                Color(red: 0.02, green: 0.52, blue: 0.96).opacity(0.9),
                                Color(red: 0.01, green: 0.30, blue: 0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 1.2, height: size * 0.7)
                    .offset(x: CGFloat(sin(t * 1.2)) * (size * 0.08), y: (size * 0.08) + waveYOffset)
                    .rotationEffect(waveRotate)
                    .blendMode(.overlay)
                
                // Secondary Fluid Wave Flow
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.4, green: 0.85, blue: 1.0).opacity(0.6),
                                Color(red: 0.1, green: 0.35, blue: 0.9).opacity(0.2)
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    )
                    .frame(width: size * 1.0, height: size * 0.55)
                    .offset(x: CGFloat(cos(t * 1.4)) * -(size * 0.07), y: -(size * 0.05) - waveYOffset)
                    .rotationEffect(-waveRotate * 0.7)
                    .blendMode(.screen)
                
                // 4. Refraction Grain / Micro-Ripple Pixel Texture Lines
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .stroke(Color.white.opacity(0.12 - Double(index) * 0.018), lineWidth: 0.8)
                        .frame(width: CGFloat(size * 0.88 - CGFloat(index * 14)), height: CGFloat(size * 0.88 - CGFloat(index * 14)))
                        .offset(
                            x: CGFloat(sin(Double(index) * 1.4 + t) * (size * 0.025)),
                            y: CGFloat(cos(Double(index) * 1.4 + t) * (size * 0.025))
                        )
                }
                
                // 5. Pure Bright White Top Highlights (Exact match to top dome)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color(red: 0.85, green: 0.96, blue: 1.0).opacity(0.6),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.42, y: 0.28),
                            startRadius: 0,
                            endRadius: size * 0.5
                        )
                    )
                    .frame(width: size, height: size)
                
                // 6. Specular Rim Ring
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.2)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .scaleEffect(baseScale)
            .shadow(color: Color(red: 0.0, green: 0.6, blue: 1.0).opacity(0.5), radius: size * 0.2, x: 0, y: size * 0.05)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Recreated Three.js AI Orb from Web UI
public struct UnisonAIEnergyOrb: View {
    @ObservedObject var db = FirestoreService.shared
    @ObservedObject var speechRecognizer = SpeechRecognizer.shared
    var isRecording: Bool = false
    var size: CGFloat = 160.0
    
    public init(isRecording: Bool = false, size: CGFloat = 160.0) {
        self.isRecording = isRecording
        self.size = size
    }
    
    public var body: some View {
        TimelineView(.animation) { timeline in
            OrbContentView(
                time: timeline.date.timeIntervalSinceReferenceDate,
                isSendingMessage: db.isSendingMessage,
                isRecording: isRecording,
                audioLevel: speechRecognizer.audioLevel,
                size: size
            )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Canvas Previews
struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChatView()
                .preferredColorScheme(.dark)
                .previewDevice("iPad Pro (11-inch)")
            
            ChatView()
                .preferredColorScheme(.dark)
                .previewDevice("iPhone 15 Pro")
        }
    }
}

// MARK: - Custom Shapes for Chrome-Style Web Tabs
struct RoundedTopCornersShape: Shape {
    var radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                    radius: radius,
                    startAngle: Angle(degrees: 180),
                    endAngle: Angle(degrees: 270),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                    radius: radius,
                    startAngle: Angle(degrees: 270),
                    endAngle: Angle(degrees: 360),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

struct TopLeftRightOutlineShape: Shape {
    var radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                    radius: radius,
                    startAngle: Angle(degrees: 180),
                    endAngle: Angle(degrees: 270),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                    radius: radius,
                    startAngle: Angle(degrees: 270),
                    endAngle: Angle(degrees: 360),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

// MARK: - Beautiful Custom SMS/Text Dispatch Modal Sheet
struct SMSComposerSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var recipient: String
    @Binding var smsBodyText: String
    
    @State private var useSimulatedDispatch = false
    @State private var showingDispatchSuccess = false
    @State private var isSending = false
    
    init(recipient: Binding<String>, body: Binding<String>) {
        self._recipient = recipient
        self._smsBodyText = body
    }
    
    private var simulatedDispatchButton: some View {
        VStack(spacing: 12) {
            Button(action: {
                isSending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    isSending = false
                    showingDispatchSuccess = true
                    SpeechManager.shared.speak("Secure text dispatch node of \(smsBodyText.count) characters simulated successfully.")
                }
            }) {
                HStack {
                    if isSending {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: "paperplane.fill")
                        Text("TEST SIMULATED DISPATCH")
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.cyan)
                .cornerRadius(25)
            }
            .disabled(recipient.isEmpty || smsBodyText.isEmpty || isSending)
            .padding(.horizontal, 24)
            
            Text("[Simulator] iOS carrier hardware not detected (Simulator fallback active). Simulated dispatch transmits secure metadata logs directly to Unison nodes.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // High-fidelity banner
                VStack(spacing: 8) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.cyan)
                        .padding(.top, 16)
                    
                    Text("NATIVE CARRIER COUPLING")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(3.0)
                        .foregroundColor(.cyan)
                    
                    Text("Dispatch secure real-time message nodes via native iOS cellular services to standard contacts.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                // Form Container
                VStack(spacing: 16) {
                    // Recipient Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECIPIENT CELL PHONE NUMBER")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.white.opacity(0.3))
                                .font(.system(size: 14))
                            
                            TextField("Recipient cellular number...", text: $recipient)
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .textFieldStyle(.plain)
                                #if os(iOS)
                                .keyboardType(.phonePad)
                                #endif
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    
                    // Message Body Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MESSAGE DATA BODY NODE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        
                        ZStack(alignment: .topLeading) {
                            if smsBodyText.isEmpty {
                                Text("Type text node message...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.25))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 8)
                            }
                            
                            TextEditor(text: $smsBodyText)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .background(Color.clear)
                                .padding(4)
                                .frame(height: 100)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    #if os(iOS) && canImport(MessageUI)
                    if MFMessageComposeViewController.canSendText() {
                        // Real Apple Carrier dispatch
                        SMSPresenterButton(recipient: recipient, messageBody: smsBodyText) {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .frame(height: 50)
                        .padding(.horizontal, 24)
                    } else {
                        simulatedDispatchButton
                    }
                    #else
                    simulatedDispatchButton
                    #endif
                }
                .padding(.bottom, 24)
            }
            .background(Color.clear.ignoresSafeArea())
            .navigationTitle("Unison SMS Console")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CLOSE") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("CLOSE") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                }
                #endif
            }
            .alert(isPresented: $showingDispatchSuccess) {
                Alert(
                    title: Text("TRANSMISSION COMPLETE"),
                    message: Text("Successfully logged dispatch of real-time text node to \(recipient)."),
                    dismissButton: .default(Text("DISMISS")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                )
            }
        }
    }
}

#if os(iOS) && canImport(MessageUI)
// MARK: - Native SMS Helper Presenter Button
struct SMSPresenterButton: View {
    let recipient: String
    let messageBody: String
    let onComplete: () -> Void
    
    @State private var isShowingSMSView = false
    
    var body: some View {
        Button(action: {
            isShowingSMSView = true
        }) {
            HStack {
                Image(systemName: "paperplane.fill")
                Text("DISPATCH NATIVE TEXT")
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.cyan)
            .cornerRadius(25)
        }
        .sheet(isPresented: $isShowingSMSView) {
            SMSComposeView(recipient: recipient, body: messageBody)
        }
    }
}
#endif

// MARK: - Real-Time @ Mention Context Dropdown Menu (matching user screenshot)
public struct MentionAutocompleteMenu: View {
    let filterText: String
    let onSelect: (String) -> Void
    
    let items: [(title: String, icon: String, tag: String)] = [
        ("Files", "doc.text", "@Files"),
        ("Directories", "folder", "@Directories"),
        ("Code Context Items", "chevron.left.slash.chevron.right", "@CodeContext"),
        ("Code Context Items", "chevron.left.slash.chevron.right", "@CodeContextItems"),
        ("Rules", "doc.plaintext", "@Rules"),
        ("Terminal", "terminal", "@Terminal"),
        ("Conversation", "bubble.left", "@Conversation"),
        ("MCP Servers", "hammer", "@MCPServers")
    ]
    
    var filteredItems: [(title: String, icon: String, tag: String)] {
        let clean = filterText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "").lowercased()
        if clean.isEmpty { return items }
        return items.filter { $0.title.lowercased().contains(clean) || $0.tag.lowercased().contains(clean) }
    }
    
    public init(filterText: String = "", onSelect: @escaping (String) -> Void) {
        self.filterText = filterText
        self.onSelect = onSelect
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredItems.enumerated()), id: \.offset) { index, item in
                Button(action: {
                    onSelect(item.tag)
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 18, alignment: .leading)
                        
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if index < filteredItems.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.13, green: 0.13, blue: 0.14))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: -6)
    }
}

// MARK: - Real-Time Slash Command Autocomplete Menu (matching user screenshot)
public struct SlashCommandAutocompleteMenu: View {
    let filterText: String
    let onSelect: (String) -> Void
    
    let items: [(name: String, description: String, icon: String)] = [
        ("goal", "Run until the specified goal is completely finished", "chevron.left.slash.chevron.right"),
        ("schedule", "Run an instruction on a recurring schedule or as a one-time timer", "chevron.left.slash.chevron.right"),
        ("grill-me", "Interview me to align on a plan", "chevron.left.slash.chevron.right"),
        ("learn", "Reflect on recent successes or corrections to capture reusable skills or rules", "chevron.left.slash.chevron.right"),
        ("help", "Documentation of all @ and / features", "questionmark.circle.fill"),
        ("clear", "Clear active conversation history", "trash.fill"),
        ("terminal", "Execute workspace shell command", "terminal.fill")
    ]
    
    var filteredItems: [(name: String, description: String, icon: String)] {
        let clean = filterText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "").lowercased()
        if clean.isEmpty { return items }
        return items.filter { $0.name.lowercased().contains(clean) || $0.description.lowercased().contains(clean) }
    }
    
    public init(filterText: String = "", onSelect: @escaping (String) -> Void) {
        self.filterText = filterText
        self.onSelect = onSelect
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredItems.enumerated()), id: \.offset) { index, item in
                Button(action: {
                    onSelect("/" + item.name)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 16, alignment: .leading)
                        
                        Text(item.name)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                        
                        Text(item.description)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if index < filteredItems.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.13, green: 0.13, blue: 0.14))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: -6)
    }
}

// MARK: - Human-in-the-Loop Confirmation Modal Card (Transformed Chat Input Area)
public struct HumanInTheLoopConfirmationCard: View {
    let msg: ChatMessage
    @ObservedObject var db = FirestoreService.shared
    @State private var selectedOptionIndex: Int = 1
    
    public init(msg: ChatMessage) {
        self.msg = msg
    }
    
    public var body: some View {
        let command = msg.pendingApprovalCommand ?? msg.commandExecuted ?? "npx tsc --noEmit"
        let baseCmd = command.components(separatedBy: " ").first ?? "npx"
        
        VStack(alignment: .leading, spacing: 8) {
            // 1. Header: >_ Allow running this command?
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                Text("Allow running this command?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // 2. Command Code Snippet Box (npx tsc --noEmit)
            VStack(alignment: .leading, spacing: 0) {
                Text(command)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            .cornerRadius(6)
            
            // 3. Numbered Option List (Radio Group)
            VStack(alignment: .leading, spacing: 4) {
                // Option 1: Yes, allow this time
                Button(action: { selectedOptionIndex = 1 }) {
                    HStack(spacing: 10) {
                        Text("1")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(selectedOptionIndex == 1 ? 0.9 : 0.4))
                            .frame(width: 18, height: 18)
                            .background(Color.white.opacity(selectedOptionIndex == 1 ? 0.15 : 0.05))
                            .cornerRadius(4)
                        
                        Text("Yes, allow this time")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(selectedOptionIndex == 1 ? 1.0 : 0.75))
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(selectedOptionIndex == 1 ? Color.white.opacity(0.08) : Color.clear)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedOptionIndex == 1 ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Option 2: Yes, and always allow '<baseCmd>'
                Button(action: { selectedOptionIndex = 2 }) {
                    HStack(spacing: 10) {
                        Text("2")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(selectedOptionIndex == 2 ? 0.9 : 0.4))
                            .frame(width: 18, height: 18)
                            .background(Color.white.opacity(selectedOptionIndex == 2 ? 0.15 : 0.05))
                            .cornerRadius(4)
                        
                        Text("Yes, and always allow '\(baseCmd)'")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(selectedOptionIndex == 2 ? 1.0 : 0.75))
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(selectedOptionIndex == 2 ? Color.white.opacity(0.08) : Color.clear)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedOptionIndex == 2 ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Option 3: No (tell the agent what to do instead)
                Button(action: { selectedOptionIndex = 3 }) {
                    HStack(spacing: 10) {
                        Text("3")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(selectedOptionIndex == 3 ? 0.9 : 0.4))
                            .frame(width: 18, height: 18)
                            .background(Color.white.opacity(selectedOptionIndex == 3 ? 0.15 : 0.05))
                            .cornerRadius(4)
                        
                        Text("No (tell the agent what to do instead)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(selectedOptionIndex == 3 ? 1.0 : 0.75))
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(selectedOptionIndex == 3 ? Color.white.opacity(0.08) : Color.clear)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedOptionIndex == 3 ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // 4. Action Footer (Skip & Submit ↵)
            HStack(spacing: 10) {
                Spacer()
                
                Button(action: {
                    db.denyPendingCommand(msgId: msg.id)
                }) {
                    Text("Skip")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help("Skip permission request")
                
                Button(action: {
                    if selectedOptionIndex == 3 {
                        db.denyPendingCommand(msgId: msg.id)
                    } else {
                        db.approvePendingCommand(msgId: msg.id, option: selectedOptionIndex)
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("Submit")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "return")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.2, green: 0.5, blue: 0.95))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.13, green: 0.13, blue: 0.15))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
