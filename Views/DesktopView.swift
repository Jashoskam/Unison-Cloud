import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Primary Workspace Shell with updated Sidebar UI, Top Bar, and Companion Interface
public struct DesktopView: View {
    @ObservedObject var db = FirestoreService.shared
    @State private var activeNavIndex = 0
    @State private var isSidebarExpanded = true
    @State private var isUserMenuPresented = true
    @State private var searchField = ""
    @State private var activeSegment = 0
    @State private var promptText = ""
    @State private var operatorPrompt = "Open Calculator, click 7, and type 42"
    @State private var animateGradient = false
    @State private var isProjectsExpanded = true
    @State private var isRecentsExpanded = true
    @State private var isSettingsPresented = false
    @StateObject private var overlayService = SystemOverlayService.shared
    @StateObject private var audioService = NativeAudioService.shared
    
    public init() {}
    
    public var body: some View {
        ZStack {
            #if os(macOS)
            HStack(spacing: 0) {
                if isSidebarExpanded {
                    sidebarContent
                    .frame(width: 260)
                    .background(
                        ZStack {
                            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                            Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.40)
                        }
                    )
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 1),
                        alignment: .trailing
                    )
                    .foregroundColor(.white)
                }
                
                mainWorkspaceContent
            }
            .ignoresSafeArea()
            #else
            ZStack(alignment: .leading) {
                mainWorkspaceContent
                
                if isSidebarExpanded {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isSidebarExpanded = false
                            }
                        }
                        .transition(.opacity)
                    
                    sidebarContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .background(Color.black.ignoresSafeArea())
                        .foregroundColor(.white)
                        .transition(.move(edge: .leading))
                        .zIndex(1)
                }
            }
            #endif
            
            if isSettingsPresented {
                SettingsView(isPresented: $isSettingsPresented)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
    }
    
    private func launchNotesWithOverlay() {
        #if os(macOS)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.allowsRunningApplicationSubstitution = false

        // Post chat message starting the computer use demo
        let initMsg = ChatMessage(
            id: UUID().uuidString,
            role: "model",
            content: "🖥️ **Initiating Computer Use Demo: Opening Apple Notes...**\n• Target Bundle ID: `com.apple.Notes`\n• Action Plan: Launch Notes -> Focus Window -> Create New Note (Cmd+N) -> Type Note Body",
            thoughts: "Executing automated Computer Use task to open Notes app and create a new note.",
            createdAt: Date()
        )
        db.messages.append(initMsg)

        if let notesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") {
            NSWorkspace.shared.openApplication(at: notesAppURL, configuration: configuration) { app, error in
                if let error = error {
                    print("Failed to launch Notes: \(error)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    self.showNotesOverlayWhenReady()
                }
            }
        } else if let notesAppPath = URL(string: "file:///Applications/Notes.app") {
            NSWorkspace.shared.openApplication(at: notesAppPath, configuration: configuration) { app, error in
                if let error = error {
                    print("Failed to launch Notes from fallback path: \(error)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    self.showNotesOverlayWhenReady()
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.showNotesOverlayWhenReady()
            }
        }
        #endif
    }

    private func showNotesOverlayWhenReady(attempts: Int = 8) {
        #if os(macOS)
        // Ensure Notes app is active and focused
        if let notesApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Notes" }) {
            notesApp.activate(options: [.activateIgnoringOtherApps])
        }

        if let frame = VisualOverlayWindowController.windowFrame(forAppBundleIdentifier: "com.apple.Notes") {
            // 1. Show the overlay canvas
            VisualOverlayWindowController.shared.show()
            
            // 2. Set target app to Notes so it highlights the window with a glowing border
            let notesApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Notes" })
            VirtualCursorManager.shared.selectedTargetApp = RunningAppInfo(
                name: "Notes",
                bundleIdentifier: "com.apple.Notes",
                processIdentifier: notesApp?.processIdentifier ?? 0
            )
            
            VirtualCursorManager.shared.activeDemoMode = "Computer Use Operator"
            VirtualCursorManager.shared.activeDemoPrompt = "Opening Notes & Typing New Note"
            VirtualCursorManager.shared.isVisible = true
            
            // 3. Move cursor to New Note button / top action bar area
            let newNotePoint = CGPoint(x: frame.minX + 160, y: frame.minY + 50)
            VirtualCursorManager.shared.animateTo(targetPoint: newNotePoint)
            VirtualCursorManager.shared.currentActionStatus = "Focusing Notes Application"
            
            // 4. Click New Note / Dispatch Cmd+N
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                VirtualCursorManager.shared.currentActionStatus = "Creating New Note (Cmd+N)"
                VirtualCursorManager.shared.isClicking = true
                
                // Synthesize mouse click and shortcut Cmd+N to create a new note in Notes app
                _ = EventSynthesizer.shared.postCGEventMouseClick(at: newNotePoint)
                EventSynthesizer.shared.postKeyCombo("cmd+n")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    VirtualCursorManager.shared.isClicking = false
                    
                    // 5. Move cursor into note body area and click to focus cursor inside text canvas
                    let noteBodyPoint = CGPoint(x: frame.minX + frame.width * 0.5, y: frame.minY + frame.height * 0.4)
                    VirtualCursorManager.shared.animateTo(targetPoint: noteBodyPoint)
                    VirtualCursorManager.shared.currentActionStatus = "Focusing Note Canvas"
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        VirtualCursorManager.shared.isClicking = true
                        _ = EventSynthesizer.shared.postCGEventMouseClick(at: noteBodyPoint)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            VirtualCursorManager.shared.isClicking = false
                            VirtualCursorManager.shared.currentActionStatus = "Typing Note Content"
                            
                            // 6. Type the demo note content line-by-line character-by-character
                            let noteText = "📝 UNISON Computer Use Autonomous Demo\n\n- Task: Open Notes & Type New Note\n- Status: Executed successfully via CGEvent & Accessibility APIs\n- Timestamp: \(Date().formatted(date: .numeric, time: .shortened))"
                            
                            let chars = Array(noteText)
                            for (index, char) in chars.enumerated() {
                                let delay = Double(index) * 0.06
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    let charStr = String(char)
                                    VirtualCursorManager.shared.pressedKey = charStr == "\n" ? "RETURN" : charStr
                                    EventSynthesizer.shared.postKeyboardEvent(string: charStr)
                                }
                            }
                            
                            let totalTypingDelay = Double(chars.count) * 0.06 + 0.5
                            DispatchQueue.main.asyncAfter(deadline: .now() + totalTypingDelay) {
                                VirtualCursorManager.shared.pressedKey = nil
                                VirtualCursorManager.shared.currentActionStatus = "✅ Note Created Successfully!"
                                
                                // Post completed message in chat
                                let resultText = """
                                ✅ **Computer Use Demo Complete!**
                                • **Target App:** Apple Notes (`com.apple.Notes`)
                                • **Actions Completed:**
                                  1. Launched & focused Notes.app window
                                  2. Triggered `Command + N` shortcut for new note
                                  3. Positioned cursor and focused text editor canvas
                                  4. Synthesized character key stream into Notes document
                                """
                                let resultMsg = ChatMessage(
                                    id: UUID().uuidString,
                                    role: "model",
                                    content: resultText,
                                    thoughts: "Computer use task finished: Created and typed new note in Apple Notes.",
                                    createdAt: Date()
                                )
                                self.db.messages.append(resultMsg)
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    VirtualCursorManager.shared.currentActionStatus = nil
                                    VirtualCursorManager.shared.activeDemoPrompt = nil
                                    VirtualCursorManager.shared.activeDemoMode = nil
                                }
                            }
                        }
                    }
                }
            }
            return
        }

        if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.showNotesOverlayWhenReady(attempts: attempts - 1)
            }
        } else {
            VisualOverlayWindowController.shared.show()
            VirtualCursorManager.shared.activeDemoMode = "Computer Use Operator"
            VirtualCursorManager.shared.activeDemoPrompt = "Notes active - fallback typing mode"
            VirtualCursorManager.shared.isVisible = true
            let fallbackPoint = CGPoint(x: 400, y: 300)
            VirtualCursorManager.shared.animateTo(targetPoint: fallbackPoint)
            
            // Fallback typing attempt
            EventSynthesizer.shared.postKeyCombo("cmd+n")
            let fallbackText = "📝 UNISON Computer Use Demo Note"
            EventSynthesizer.shared.postKeyboardEvent(string: fallbackText)
            
            VirtualCursorManager.shared.currentActionStatus = "✅ Note Typed (Fallback)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                VirtualCursorManager.shared.currentActionStatus = nil
                VirtualCursorManager.shared.activeDemoPrompt = nil
                VirtualCursorManager.shared.activeDemoMode = nil
            }
        }
        #endif
    }

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header controls positioned safely below macOS window traffic light buttons (red/yellow/green)
            HStack(spacing: 14) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSidebarExpanded = false
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.70))
                }
                .buttonStyle(.plain)
                .help("Toggle Sidebar")
                
                Button(action: {}) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                
                Button(action: {}) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                }
                .buttonStyle(.plain)
                
                Button(action: {}) {
                    Image(systemName: "bell")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 48) // Safe clearance below macOS traffic lights
            .padding(.bottom, 8)
            
            // App name dropdown selector: "UNISON ⌄"
            HStack(spacing: 4) {
                Button(action: {}) {
                    HStack(spacing: 5) {
                        Text("UNISON")
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // New chat item: Gives clean black chat space immediately without forcing immediate tab
                    Button(action: {
                        db.createWorkspaceConversation(title: "New chat", type: "chat") { newId in
                            db.selectedConversationId = newId
                            db.messages = []
                            db.fetchLiveMessages(conversationId: newId)
                        }
                        activeNavIndex = 0
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.75))
                                .frame(width: 18, alignment: .leading)
                            Text("New chat")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // Scheduled item
                    Button(action: {
                        activeNavIndex = 998
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .font(.system(size: 14))
                                .foregroundColor(activeNavIndex == 998 ? .cyan : .white.opacity(0.75))
                                .frame(width: 18, alignment: .leading)
                            Text("Scheduled")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(activeNavIndex == 998 ? .white : .white.opacity(0.9))
                            Spacer()
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(activeNavIndex == 998 ? Color.white.opacity(0.08) : Color.clear)
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // Plugins item
                    Button(action: {
                        activeNavIndex = 999
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "puzzlepiece")
                                .font(.system(size: 14))
                                .foregroundColor(activeNavIndex == 999 ? .cyan : .white.opacity(0.75))
                                .frame(width: 18, alignment: .leading)
                            Text("Plugins")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(activeNavIndex == 999 ? .white : .white.opacity(0.9))
                            Spacer()
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(activeNavIndex == 999 ? Color.white.opacity(0.08) : Color.clear)
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // 1. Projects Section Header
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Projects")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                            
                            Spacer()
                            
                            Button(action: {
                                openProjectFolderPicker()
                            }) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                            .buttonStyle(.plain)
                            .help("Filter projects")
                            
                            Button(action: {
                                openProjectFolderPicker()
                            }) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Open workspace directory")
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        
                        // Workspace Folder Node (e.g. 📁 unison +)
                        let activeFolder = (db.activeWorkspaceDirectoryPath as NSString?)?.lastPathComponent ?? "unison"
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                            Text(activeFolder)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Button(action: {
                                // Use the workspace directory path as parentId for proper hierarchy
                                let projectParentId = db.activeWorkspaceDirectoryPath ?? activeFolder
                                db.createWorkspaceConversation(title: "New \(activeFolder) Chat", type: "project", parentId: projectParentId) { newId in
                                    db.selectedConversationId = newId
                                    db.messages = []
                                }
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Make a new chat tab under \(activeFolder)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        
                        // Active Project Item (e.g., Cloning ChatGPT Project... 19h)
                        if let firstConvo = db.conversations.first {
                            let isSelected = db.selectedConversationId == firstConvo.id
                            Button(action: {
                                db.selectedConversationId = firstConvo.id
                                db.messages = []
                                db.fetchLiveMessages(conversationId: firstConvo.id)
                            }) {
                                HStack(spacing: 8) {
                                    Text(firstConvo.title)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                        .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("19h")
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 16)
                        }
                    }
                    .padding(.bottom, 12)
                    
                    // 2. Conversations Section Header with + button
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Conversations")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                            
                            Spacer()
                            
                            Button(action: {
                                db.createWorkspaceConversation(title: "New Chat", type: "chat") { newId in
                                    db.selectedConversationId = newId
                                    db.messages = []
                                }
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                            .help("Start new conversation tab")
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        
                        // Conversations List under Active Project
                        if db.conversations.count <= 1 {
                            Text("No additional conversation tabs")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                                .padding(.leading, 12)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(Array(db.conversations.dropFirst())) { convo in
                                let isSelected = db.selectedConversationId == convo.id
                                HStack(spacing: 4) {
                                    Button(action: {
                                        db.selectedConversationId = convo.id
                                        db.messages = []
                                        db.fetchLiveMessages(conversationId: convo.id)
                                    }) {
                                        HStack(spacing: 8) {
                                            Text(convo.title)
                                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                                                .lineLimit(1)
                                            Spacer()
                                            Text("2d")
                                                .font(.system(size: 11, weight: .regular))
                                                .foregroundColor(.white.opacity(0.4))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button(action: {
                                        db.deleteWorkspaceConversation(id: convo.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundColor(.red.opacity(0.6))
                                            .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete conversation tab")
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 12)
                                .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            
            Spacer()
            
            // Popover user menu (floating card above profile)
            if isUserMenuPresented {
                VStack(alignment: .leading, spacing: 0) {
                    // Top profile header in menu
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(red: 0.18, green: 0.45, blue: 0.72))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text("JA")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        
                        Text(db.currentUserEmail?.components(separatedBy: "@").first ?? "jashoskam")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.bottom, 4)
                    
                    // Menu Options
                    Button(action: {}) {
                        HStack(spacing: 10) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 13))
                                .foregroundColor(.cyan)
                                .frame(width: 18, alignment: .leading)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Usage remaining")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                    Spacer()
                                    Text("\(db.tokensRemainingPercent)% Left")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.cyan)
                                }
                                Text("\(db.tokensRemainingFormatted) • Pro Tier")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {}) {
                        HStack(spacing: 10) {
                            Image(systemName: "pawprint")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 18, alignment: .leading)
                            
                            Text("Show pet")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {}) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 18, alignment: .leading)
                            
                            Text("Upgrade for higher limits")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Spacer()
                            
                            Image(systemName: "globe")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        isUserMenuPresented = false
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isSettingsPresented = true
                        }
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 18, alignment: .leading)
                            
                            Text("Settings")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Spacer()
                            
                            Text("⌘,")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        db.signOut()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 18, alignment: .leading)
                            
                            Text("Log out")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.15, green: 0.15, blue: 0.16))
                        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            
            // Bottom User Profile Row
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isUserMenuPresented.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(red: 0.18, green: 0.45, blue: 0.72))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text("JA")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        )
                    
                    Text(db.currentUserEmail?.components(separatedBy: "@").first ?? "jashoskam")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
    }

    private func openProjectFolderPicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Project Folder"
        panel.title = "Choose Workspace Directory for AI Project"
        
        panel.begin { response in
            if response == .OK, let selectedUrl = panel.url {
                let folderName = selectedUrl.lastPathComponent
                let folderPath = selectedUrl.path
                
                db.createWorkspaceConversation(title: folderName, type: "project") { newId in
                    db.selectedConversationId = newId
                    db.messages = []
                    db.activeWorkspaceDirectoryPath = folderPath
                    db.fetchLiveMessages(conversationId: newId)
                    
                    let welcomeMsg = ChatMessage(
                        id: UUID().uuidString,
                        role: "model",
                        content: "📁 **Project Workspace Connected:** `\(folderPath)`\nUnison AI can now read project files, write code, run terminal commands, and assist with workspace files in real time.",
                        thoughts: "Project directory linked: \(folderPath)",
                        createdAt: Date()
                    )
                    db.messages.append(welcomeMsg)
                }
            }
        }
        #endif
    }
    
    @ViewBuilder
    private var mainWorkspaceContent: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.02).ignoresSafeArea()
            
            if activeNavIndex == 999 {
                PluginsView(isSidebarExpanded: $isSidebarExpanded, onLaunchComputerUse: {
                    self.launchNotesWithOverlay()
                })
            } else if activeNavIndex == 998 {
                ScheduledTasksView(isSidebarExpanded: $isSidebarExpanded)
            } else if activeNavIndex < db.sduiTabs.count {
                let activeTab = db.sduiTabs[activeNavIndex]
                switch activeTab.viewType {
                case "overview":
                    OverviewView(activeNavIndex: $activeNavIndex)
                case "notes":
                    NotesWorkspaceView()
                case "all_items":
                    AllItemsView(activeNavIndex: $activeNavIndex, tabs: db.sduiTabs)
                case "chat":
                    ChatView(isMobileSidebarOpen: $isSidebarExpanded, isSidebarExpanded: $isSidebarExpanded)
                case "system_hub":
                    SystemHubView()

                case "terminal":
                    TerminalView()
                case "titan_suite":
                    TitanSuiteView()
                case "canvas":
                    CanvasView()
                default:
                    ChatView(isMobileSidebarOpen: $isSidebarExpanded, isSidebarExpanded: $isSidebarExpanded)
                }
            } else {
                ChatView(isMobileSidebarOpen: $isSidebarExpanded, isSidebarExpanded: $isSidebarExpanded)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChatInterfaceView: View {
    @State private var prompt = ""
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 11))
                    Text("NEW CHAT").font(.system(size: 12, weight: .bold))
                }
                Spacer()
                Button(action: {}) {
                    Text("+ Spawn").font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.white.opacity(0.1)).cornerRadius(8)
                }.buttonStyle(.plain)
            }
            .padding(16).background(Color.white.opacity(0.02))
            
            Spacer()
            
            // Hero
            VStack(spacing: 16) {
                Image(systemName: "circle.grid.cross.fill").font(.system(size: 50))
                Text("UNISON Companion").font(.title2.bold())
                Text("Fast, minimalist artificial intelligence. Say \"Hey Unison\" to start speaking.").foregroundColor(.gray)
            }
            
            Spacer()
            
            // Input Area
            VStack {
                HStack {
                    Circle().fill(Color.green).frame(width: 24, height: 24)
                    Image(systemName: "paperclip")
                    TextField("Initialize prompt...", text: $prompt)
                    Image(systemName: "slider.horizontal.3")
                    Image(systemName: "mic")
                    Image(systemName: "arrow.right.circle.fill")
                }
                .padding(12).background(Color.black.opacity(0.6)).cornerRadius(12)
                
                HStack {
                    Text("Auto Routing").font(.caption2)
                    Spacer()
                    Text("Gemini 3.5 Flash").font(.caption2)
                }.padding(.top, 8).foregroundColor(.gray)
            }
            .padding(16).background(Color.white.opacity(0.03))
        }
    }
}

struct SidebarButton: View {
    let title: String, iconName: String, isSelected: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : .gray)
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .gray)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SegmentButton: View {
    let title: String, isSelected: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isSelected ? .white : .gray)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    let iconName: String, isSelected: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .white : .gray)
                .frame(width: 40, height: 40)
                .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

struct WorkstreamItem: View {
    let title: String, color: Color
    var body: some View {
        HStack {
            Image(systemName: "chevron.down").font(.system(size: 8))
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 13))
        }.foregroundColor(.gray)
    }
}

struct DesktopView_Previews: PreviewProvider {
    static var previews: some View {
        DesktopView().frame(width: 1000, height: 800)
    }
}

struct OverviewView: View {
    @Binding var activeNavIndex: Int
    @ObservedObject var db = FirestoreService.shared
    
    @State private var showNewNoteDialog = false
    @State private var showNewEventDialog = false
    @State private var showNewTaskDialog = false
    
    @State private var newNoteTitle = ""
    @State private var newNoteDesc = ""
    
    @State private var newEventSummary = ""
    @State private var newEventTime = Date()
    @State private var newEventDesc = ""
    
    @State private var newTaskTitle = ""
    @State private var newTaskNotes = ""
    @State private var newTaskPriority = "medium"
    
    private func formatEventTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: isoString) {
            let outFormatter = DateFormatter()
            outFormatter.dateFormat = "MMM d, h:mm a"
            return outFormatter.string(from: date)
        }
        return isoString
            .replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: "Z", with: "")
            .prefix(16)
            .description
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Top Actions
                    HStack {
                        // Quick Action Buttons
                        HStack(spacing: 12) {
                            Button(action: {
                                showNewNoteDialog = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "note.text.badge.plus")
                                        .font(.system(size: 13))
                                    Text("New Note")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.12).background(.ultraThinMaterial))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                showNewEventDialog = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar.badge.plus")
                                        .font(.system(size: 13))
                                    Text("New Event")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.purple.opacity(0.12).background(.ultraThinMaterial))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                showNewTaskDialog = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checklist.on.clipboard")
                                        .font(.system(size: 13))
                                    Text("New Task")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.12).background(.ultraThinMaterial))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 16) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06).background(.ultraThinMaterial))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Calendar Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 6) {
                                Text("Calendar")
                                    .font(.system(size: 20, weight: .bold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "calendar")
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 20)
                        
                        VStack(alignment: .leading, spacing: 14) {
                            if db.calendarEvents.isEmpty {
                                Text("No upcoming meetings or events armed.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(db.calendarEvents) { event in
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.yellow)
                                            .frame(width: 3, height: 32)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.summary)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                            HStack {
                                                Text(formatEventTime(event.startTime))
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.gray)
                                                if !event.description.isEmpty {
                                                    Text("•")
                                                        .foregroundColor(.gray)
                                                    Text(event.description)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.gray)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                        Spacer()
                                        
                                        Button(action: {
                                            let updated = db.calendarEvents.filter { $0.id != event.id }
                                            db.saveMeetingsToServer(meetings: updated)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 12))
                                                .foregroundColor(.gray.opacity(0.5))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.02))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(18)
                        .padding(.horizontal, 20)
                    }
                    
                    // Tasks Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 6) {
                                Text("Tasks")
                                    .font(.system(size: 20, weight: .bold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "checklist")
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 20)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            if db.tasksList.isEmpty {
                                Text("No registered items in tasks registry.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(db.tasksList) { task in
                                    let isChecked = task.columnId == "done"
                                    HStack(spacing: 12) {
                                        Button(action: {
                                            var updated = db.tasksList
                                            if let idx = updated.firstIndex(where: { $0.id == task.id }) {
                                                updated[idx].columnId = isChecked ? "todo" : "done"
                                                db.saveTasksToServer(tasks: updated)
                                            }
                                        }) {
                                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 18))
                                                .foregroundColor(isChecked ? .blue : .gray)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(isChecked ? .gray : .white)
                                                .strikethrough(isChecked)
                                            HStack(spacing: 6) {
                                                Text(task.priority.uppercased())
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(task.priority == "high" ? .red : (task.priority == "medium" ? .orange : .green))
                                                if !task.notes.isEmpty {
                                                    Text("•")
                                                        .foregroundColor(.gray)
                                                    Text(task.notes)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.gray)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                        Spacer()
                                        
                                        Button(action: {
                                            let updated = db.tasksList.filter { $0.id != task.id }
                                            db.saveTasksToServer(tasks: updated)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 12))
                                                .foregroundColor(.gray.opacity(0.5))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            
                            Divider().background(Color.white.opacity(0.08))
                            
                            Button(action: {
                                showNewTaskDialog = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 18))
                                        .foregroundColor(.gray.opacity(0.7))
                                    Text("Add task")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray.opacity(0.7))
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(18)
                        .padding(.horizontal, 20)
                    }
                    
                    // Notes Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 6) {
                                Text("Notes")
                                    .font(.system(size: 20, weight: .bold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            
                            Spacer()
                            
                            HStack(spacing: 16) {
                                Text("Recents")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                if db.jottingsList.isEmpty {
                                    Text("No workspace jottings found.")
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 16)
                                } else {
                                    ForEach(db.jottingsList) { jotting in
                                        Button(action: {
                                            db.activeNoteTitle = jotting.label
                                            db.activeNoteStatus = "Synced"
                                            db.activeNoteContent = "Notebook - \(jotting.label)\n\n\(jotting.description)"
                                            activeNavIndex = 1 // Switch to Notes workspace
                                        }) {
                                            VStack(alignment: .leading, spacing: 12) {
                                                HStack {
                                                    Image(systemName: "doc.text.fill")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.white.opacity(0.7))
                                                    Text("Notebook")
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundColor(.white.opacity(0.7))
                                                    Spacer()
                                                }
                                                
                                                Text(jotting.label)
                                                    .font(.system(size: 15, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                
                                                Text(jotting.description)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.gray)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                                
                                                Spacer()
                                            }
                                            .padding(16)
                                            .frame(width: 200, height: 135, alignment: .topLeading)
                                            .background(Color.white.opacity(0.04))
                                            .cornerRadius(18)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18)
                                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    // Padding for bottom floating tab bar
                    Color.clear.frame(height: 100)
                }
            }
            
            // Bottom Glassmorphic Navigation Bar
            HStack(spacing: 24) {
                HStack(spacing: 24) {
                    Button(action: { activeNavIndex = 0 }) {
                        BottomBarNavItem(iconName: "square.grid.2x2.fill", label: "Overview", isSelected: activeNavIndex == 0)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { activeNavIndex = 1 }) {
                        BottomBarNavItem(iconName: "doc.text", label: "Notes", isSelected: activeNavIndex == 1)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        // Scroll or switch to Notes (Calendar is in Overview)
                    }) {
                        BottomBarNavItem(iconName: "calendar", label: "Calendar", isSelected: false)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        // Scroll or switch to Notes (Tasks is in Overview)
                    }) {
                        BottomBarNavItem(iconName: "checkmark.circle", label: "Tasks", isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08).background(.ultraThinMaterial))
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                
                Button(action: {
                    showNewNoteDialog = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.12).background(.ultraThinMaterial))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
            .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
            .ignoresSafeArea(edges: .bottom)
            
            // Dialog overlays
            if showNewNoteDialog {
                DialogOverlay(title: "New Note", isPresented: $showNewNoteDialog) {
                    VStack(alignment: .leading, spacing: 14) {
                        CustomTextField(placeholder: "Title", text: $newNoteTitle)
                        CustomTextField(placeholder: "Description", text: $newNoteDesc)
                        
                        HStack {
                            Spacer()
                            DialogButton(title: "Cancel", isPrimary: false) {
                                showNewNoteDialog = false
                            }
                            DialogButton(title: "Save", isPrimary: true) {
                                if !newNoteTitle.isEmpty {
                                    let jotting = JottingFile(
                                        name: "\(newNoteTitle.lowercased().replacingOccurrences(of: " ", with: "_")).ipynb",
                                        label: newNoteTitle,
                                        description: newNoteDesc
                                    )
                                    var updated = db.jottingsList
                                    updated.append(jotting)
                                    db.saveJottingsToServer(jottings: updated)
                                    
                                    newNoteTitle = ""
                                    newNoteDesc = ""
                                    showNewNoteDialog = false
                                }
                            }
                        }
                    }
                }
            }
            
            if showNewEventDialog {
                DialogOverlay(title: "New Event", isPresented: $showNewEventDialog) {
                    VStack(alignment: .leading, spacing: 14) {
                        CustomTextField(placeholder: "Event Title", text: $newEventSummary)
                        CustomTextField(placeholder: "Description (optional)", text: $newEventDesc)
                        
                        DatePicker("Start Time", selection: $newEventTime)
                            .datePickerStyle(.compact)
                            .foregroundColor(.white)
                            .colorScheme(.dark)
                        
                        HStack {
                            Spacer()
                            DialogButton(title: "Cancel", isPrimary: false) {
                                showNewEventDialog = false
                            }
                            DialogButton(title: "Save", isPrimary: true) {
                                if !newEventSummary.isEmpty {
                                    let isoFormatter = ISO8601DateFormatter()
                                    let startTimeString = isoFormatter.string(from: newEventTime)
                                    let newEvent = CalendarEvent(
                                        summary: newEventSummary,
                                        startTime: startTimeString,
                                        description: newEventDesc,
                                        createdAt: isoFormatter.string(from: Date()),
                                        recurrence: "none"
                                    )
                                    var updated = db.calendarEvents
                                    updated.append(newEvent)
                                    db.saveMeetingsToServer(meetings: updated)
                                    
                                    newEventSummary = ""
                                    newEventDesc = ""
                                    showNewEventDialog = false
                                }
                            }
                        }
                    }
                }
            }
            
            if showNewTaskDialog {
                DialogOverlay(title: "New Task", isPresented: $showNewTaskDialog) {
                    VStack(alignment: .leading, spacing: 14) {
                        CustomTextField(placeholder: "Task Title", text: $newTaskTitle)
                        CustomTextField(placeholder: "Notes", text: $newTaskNotes)
                        
                        Picker("Priority", selection: $newTaskPriority) {
                            Text("Low").tag("low")
                            Text("Medium").tag("medium")
                            Text("High").tag("high")
                        }
                        .pickerStyle(.segmented)
                        .colorScheme(.dark)
                        
                        HStack {
                            Spacer()
                            DialogButton(title: "Cancel", isPrimary: false) {
                                showNewTaskDialog = false
                            }
                            DialogButton(title: "Save", isPrimary: true) {
                                if !newTaskTitle.isEmpty {
                                    let dateFormatter = DateFormatter()
                                    dateFormatter.dateFormat = "yyyy-MM-dd"
                                    let today = dateFormatter.string(from: Date())
                                    
                                    let newTask = TaskItem(
                                        title: newTaskTitle,
                                        notes: newTaskNotes,
                                        priority: newTaskPriority,
                                        columnId: "todo",
                                        updatedAt: today
                                    )
                                    var updated = db.tasksList
                                    updated.append(newTask)
                                    db.saveTasksToServer(tasks: updated)
                                    
                                    newTaskTitle = ""
                                    newTaskNotes = ""
                                    newTaskPriority = "medium"
                                    showNewTaskDialog = false
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.05).ignoresSafeArea())
    }
}

struct DialogOverlay<Content: View>: View {
    let title: String
    @Binding var isPresented: Bool
    let content: () -> Content
    
    init(title: String, isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isPresented = isPresented
        self.content = content
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                content()
            }
            .padding(20)
            .background(Color.black.opacity(0.85).background(.ultraThinMaterial))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .frame(width: 320)
        }
    }
}

struct CustomTextField: View {
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        TextField("", text: $text)
            .placeholder(when: text.isEmpty) {
                Text(placeholder)
                    .foregroundColor(.gray)
                    .font(.system(size: 13))
            }
            .textFieldStyle(PlainTextFieldStyle())
            .padding(10)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
            .foregroundColor(.white)
            .font(.system(size: 13))
    }
}

struct DialogButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isPrimary ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isPrimary ? Color.white : Color.white.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

struct BottomBarNavItem: View {
    let iconName: String
    let label: String
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .white : .gray)
            Text(label)
                .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .gray)
        }
        .frame(width: 50)
    }
}

struct OverviewStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

struct LogLineView: View {
    let time: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("[\(time)]")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.green.opacity(0.8))
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
        }
    }
}

struct AllItemsView: View {
    @Binding var activeNavIndex: Int
    let tabs: [SDUITab]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("All Workspace Components")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.green)
                    Text("Navigate to any available module in Unison OS")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        Button(action: {
                            activeNavIndex = index
                        }) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 22))
                                        .foregroundColor(.green)
                                    Spacer()
                                    if let badge = tab.badge {
                                        Text(badge)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green)
                                            .cornerRadius(6)
                                    }
                                }
                                
                                Text(tab.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.top, 8)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

struct NotesWorkspaceView: View {
    @ObservedObject var db = FirestoreService.shared
    @State private var showTemplates = false
    @State private var searchText = ""
    
    var body: some View {
        ZStack {
            // Note Editor View
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        // Go back
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Button(action: {}) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {}) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title
                        TextField("Note Title", text: Binding(
                            get: { db.activeNoteTitle },
                            set: { db.activeNoteTitle = $0 }
                        ))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        // Metadata Status Row
                        HStack(spacing: 16) {
                            HStack(spacing: 6) {
                                Image(systemName: "circle.dashed")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                Text("Status")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                            }
                            
                            Text(db.activeNoteStatus)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.6, green: 0.4, blue: 0.9).opacity(0.15))
                                .cornerRadius(8)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        // Add Field
                        Button(action: {}) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13))
                                Text("Add field")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        
                        // Content Text Area
                        TextEditor(text: Binding(
                            get: { db.activeNoteContent },
                            set: { db.activeNoteContent = $0 }
                        ))
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .frame(minHeight: 300)
                        .padding(.horizontal, 16)
                        .background(Color.clear)
                        .scrollContentBackground(.hidden)
                    }
                }
                
                // Bottom Tools Bar
                HStack {
                    HStack(spacing: 20) {
                        Button(action: {}) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {}) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            showTemplates = true
                        }) {
                            Image(systemName: "rectangle.grid.1x2")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06).background(.ultraThinMaterial))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.05, green: 0.05, blue: 0.05).ignoresSafeArea())
            .sheet(isPresented: $showTemplates) {
                TemplatesSheetView(showTemplates: $showTemplates, noteContent: Binding(
                    get: { db.activeNoteContent },
                    set: { db.activeNoteContent = $0 }
                ))
            }
        }
    }
}

struct TemplatesSheetView: View {
    @Binding var showTemplates: Bool
    @Binding var noteContent: String
    @State private var searchField = ""
    @State private var selectedTemplateIndex: Int? = nil
    
    let templates = [
        (
            title: "Meeting Notes",
            label: "Meeting notes",
            preview: """
Date and time: 15th January, 2025 at 3pm EST

Meeting Details
Main objective: define brand identity with the team
Attendees: marketing team
Facilitator: Mark P.
Location: zoom link
Duration: 50 mins

Meeting goals
Note down all the things you want to accomplish.
"""
        ),
        (
            title: "Class Notes",
            label: "Class notes",
            preview: """
This template allows you to sort out and structure your school and university notes.

1st Class
Introduction to Kant - Philosophy Lecture w/ Dr. Peytour
Date & Time: Thu, Sep 12, 2024, 2:15 PM - 4:15 PM

Audio recording
You can record directly your classes and automatically transcribe them using Evernote's Audio Recording feature.
"""
        )
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Header Bar
            HStack {
                Button(action: {
                    showTemplates = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Templates")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                
                Spacer()
                
                Button(action: {
                    if let idx = selectedTemplateIndex {
                        noteContent = templates[idx].preview
                    }
                    showTemplates = false
                }) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search templates", text: $searchField)
                    .foregroundColor(.black)
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
            
            // Templates Grid Scroll View
            ScrollView {
                HStack(spacing: 16) {
                    ForEach(0..<templates.count, id: \.self) { idx in
                        let tmpl = templates[idx]
                        Button(action: {
                            selectedTemplateIndex = idx
                        }) {
                            VStack(alignment: .leading, spacing: 10) {
                                // Miniature preview block
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tmpl.title)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.black)
                                    
                                    Text(tmpl.preview)
                                        .font(.system(size: 7))
                                        .foregroundColor(.gray)
                                        .lineLimit(10)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxHeight: 120, alignment: .topLeading)
                                }
                                .padding(12)
                                .frame(width: 160, height: 160, alignment: .topLeading)
                                .background(Color.white)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(selectedTemplateIndex == idx ? Color.blue : Color.black.opacity(0.08), lineWidth: 2)
                                )
                                .shadow(color: Color.black.opacity(0.04), radius: 5, y: 2)
                                
                                Text(tmpl.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(selectedTemplateIndex == idx ? .blue : .black.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
        }
        .background(Color(red: 0.93, green: 0.93, blue: 0.93).ignoresSafeArea())
    }
}
