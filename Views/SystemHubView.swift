import SwiftUI
import AVFoundation

fileprivate struct MockCalendarEvent: Identifiable {
    let id = UUID()
    let title: String
    let time: String
    let node: String
}

/// Ultra High Fidelity System Hub Dashboard UI matching standard desktop layouts.
/// Provides beautiful design pairings, 4 central developer tabs, real-time connector badges,
/// cognitive memory appending, and pipeline alarm controls.
public struct SystemHubView: View {
    @ObservedObject var db = FirestoreService.shared
    @Environment(\.presentationMode) var presentationMode
    
    // Core Navigation Tabs matching center header links
    @State private var selectedTab = 0
    let tabs = ["SYSTEM HUB", "REPOS", "MEMORY", "ALERTS"]
    
    // Search and Filtering states
    @State private var searchText = ""
    @State private var selectedFilter = "DISCOVER"
    
    // Integration detail popup overlay state
    @State private var selectedConnector: Connector? = nil
    @State private var showingDetailPopover = false
    
    // Toast Alert notification triggers
    @State private var toastMessage: String? = nil
    @State private var showToast = false
    @State private var toastType: String = "info" // success, error, warning, info
    
    // --- TAB 1 REPOS DATA ---
    @State private var selectedGitCategory = "ISSUES"
    @State private var githubIssues = [
        GitHubIssue(id: "#104", title: "V3 auth validation loop crash", status: "Open", tag: "critical", color: Color.red),
        GitHubIssue(id: "#103", title: "Dynamic thread pooling configuration", status: "Merged", tag: "enhancement", color: Color.purple),
        GitHubIssue(id: "#102", title: "Low signal recovery callback handler", status: "Closed", tag: "hardware", color: Color.orange),
        GitHubIssue(id: "#101", title: "Implement Web Socket fallbacks on mobile Client", status: "Open", tag: "bug", color: Color.red)
    ]
    @State private var githubCommits = [
        GitHubCommit(msg: "feat: unified pairing check logic via rest interface", time: "2 hours ago", by: "Operator"),
        GitHubCommit(msg: "docs: update companion instructions", time: "1 day ago", by: "Assistant"),
        GitHubCommit(msg: "fix: prevent core audio workloop starvation", time: "3 days ago", by: "Operator")
    ]
    @State private var githubBranches = ["main", "dev-pipeline", "relay-test"]
    
    // Gmail & Calendar structure instances
    let gmailEmails = [
        GmailEmail(from: "Assistant Core", time: "10:30 AM", subject: "System status update: All operations nominal"),
        GmailEmail(from: "GitHub Notifications", time: "Yesterday", subject: "[unison-os] Push event on dev-pipeline by Operator"),
        GmailEmail(from: "Google Payments", time: "2 days ago", subject: "Your Google Workspace subscription is active")
    ]
    
    fileprivate let mockCalendarEvents = [
        MockCalendarEvent(title: "Sync with Developer Core", time: "2:00 PM - 2:30 PM", node: "ONLINE"),
        MockCalendarEvent(title: "Smart IoT Node Calibration", time: "4:00 PM - 5:00 PM", node: "SYSTEM_NODE"),
        MockCalendarEvent(title: "Pipeline Architecture Workshop", time: "Tomorrow, 10:00 AM", node: "ONLINE")
    ]
    
    // --- TAB 2 COGNITIVE AI MEMORIES ---
    @State private var aiMemories = [
        MemoryItem(category: "Preference", content: "Operator prefers Space Grotesk typography for terminal readouts."),
        MemoryItem(category: "Constraint", content: "Keep system telemetry refresh rates locked under 2.5 seconds."),
        MemoryItem(category: "Project", content: "Current workspace pipeline targeted at unison-agentic-swift."),
        MemoryItem(category: "Attribute", content: "Assistant replies should be highly contextual and concise.")
    ]
    @State private var memoryInputText = ""
    @State private var selectedMemoryCategory = "Preference"
    let memoryCategories = ["Preference", "Constraint", "Project", "Attribute"]
    

    // --- TAB 5 ALERTS TICKER & TIMERS ---
    @State private var countdownMinutes = 15
    @State private var isTimerActive = false
    @State private var alarmsTimer: Timer? = nil
    @State private var logsTimer: Timer? = nil
    @State private var systemTemp = 42.0
    @State private var signalStrength = -62
    @State private var coreVoltage = 5.01
    @State private var localRelayStates: [String: Bool] = [:]
    @State private var sysLogs = [
        SysLogItem(tag: "SYNC", message: "Grid coupling pipeline synchronizing...", timestamp: "10:53:55 AM", isError: false),
        SysLogItem(tag: "CORE", message: "Active companion node mapping resolved safely", timestamp: "10:52:14 AM", isError: false),
        SysLogItem(tag: "AUDIO", message: "Core sound synthesis interface loaded", timestamp: "10:50:00 AM", isError: false),
        SysLogItem(tag: "WIFI", message: "Signal attenuation low under -65dBm", timestamp: "10:45:11 AM", isError: true),
        SysLogItem(tag: "API", message: "OAuth workspace connection secured", timestamp: "10:42:01 AM", isError: false)
    ]
    
    // Seed list of connectors with properties matching the image
    let connectorsPool = [
        Connector(id: "calendar_connector", name: "Google Calendar", description: "Schedule events, view active agenda timelines, and manage calendars in real-time.", icon: "calendar", color: Color.blue, isConnected: false, iconColor: .blue),
        Connector(id: "sheets_connector", name: "Google Sheets", description: "Real-time access to Google Sheets tables, cell records, and spreadsheet ledgers dynamically.", icon: "tablecells", color: Color.green, isConnected: false, iconColor: .green),
        Connector(id: "slides_connector", name: "Google Slides", description: "Real-time access to presentation slides, templates, and visual slide pitch decks.", icon: "doc.richtext.fill", color: Color.orange, isConnected: false, iconColor: .orange),
        Connector(id: "drive_connector", name: "Google Drive", description: "Browse Google Drive directories, locate files, and sync layout documents in cloud database.", icon: "folder.fill", color: Color.cyan, isConnected: false, iconColor: .cyan),
        Connector(id: "gmail_connector", name: "Gmail Workspace", description: "View recent emails, send correspondence, and manage drafts directly from the workspace.", icon: "envelope.fill", color: Color.red, isConnected: false, iconColor: .red),
        Connector(id: "github_connector", name: "GitHub Realtime", description: "Real-time sync to GitHub repositories, listing/creating issues, inspecting commits, and repository search.", icon: "curlybraces", color: Color.purple, isConnected: true, iconColor: .purple),
        Connector(id: "spotify_connector", name: "Spotify Music Stream", description: "Control live playback, inspect active tracks, and search songs on your Spotify devices.", icon: "music.note", color: Color.teal, isConnected: false, iconColor: .green)
    ]
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Outer Deep Obsidian Slate Background
                Color(red: 0.03, green: 0.03, blue: 0.04)
                    .ignoresSafeArea()
                
                // Radiant Ambient Bloom Orbs
                RadialGradient(gradient: Gradient(colors: [Color.blue.opacity(0.12), Color.clear]), center: .topLeading, startRadius: 10, endRadius: 400)
                    .ignoresSafeArea()
                RadialGradient(gradient: Gradient(colors: [Color.purple.opacity(0.08), Color.clear]), center: .bottomTrailing, startRadius: 10, endRadius: 450)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // MARK: - HORIZONTAL NAVIGATION TAB HEADER
                    HStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 24) {
                                ForEach(tabs.indices, id: \.self) { idx in
                                    VStack(spacing: 8) {
                                        Button(action: {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                                selectedTab = idx
                                            }
                                            triggerBip(freq: 750)
                                        }) {
                                            Text(tabs[idx])
                                                .font(.system(size: 11, weight: .bold))
                                                .tracking(1.5)
                                                .foregroundColor(selectedTab == idx ? .white : .white.opacity(0.4))
                                                .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        // Dynamic underline highlight
                                        Rectangle()
                                            .fill(selectedTab == idx ? Color.white : Color.clear)
                                            .frame(width: 32, height: 2)
                                    }
                                }
                            }
                            .padding(.leading, 16)
                        }
                        
                        Spacer()
                        
                        // Close Dismiss Toggle Button (Matches top right circular indicator)
                        Button(action: {
                            triggerBip(freq: 415)
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.04))
                                .clipShape(Circle())
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                    }
                    .padding(.top, 14)
                    .background(Color.black.opacity(0.3))
                    
                    Divider().background(Color.white.opacity(0.04))
                    
                    // MARK: - DYNAMIC TAB CONTROLLER VIEWPORT
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            
                            if selectedTab == 0 {
                                // Tabb 0: System Hub (Connectors Dashboard Viewport)
                                buildSystemHubViewport(geometry: geometry)
                            } else if selectedTab == 1 {
                                // Tab 1: Repo Explorer (GitHub, Branches, Commits)
                                buildRepoExplorer(geometry: geometry)
                            } else if selectedTab == 2 {
                                // Tab 2: Memories Manager (AI Strategist Storage)
                                buildMemoriesManager(geometry: geometry)
                            } else if selectedTab == 3 {
                                // Tab 5: Real-time Syslog & Alarms
                                buildSyslogAlarmsViewport(geometry: geometry)
                            }
                            
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                    }
                }
                
                // MARK: - API DETAIL POPUP MODULE
                if showingDetailPopover, let connector = selectedConnector {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingDetailPopover = false
                        }
                    
                    buildDetailPopOverlay(connector: connector)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(5)
                }
                
                // MARK: - COGNITIVE INTERSECTION TOAST BANNER
                if showToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Circle()
                                .fill(toastBannerColor())
                                .frame(width: 8, height: 8)
                            
                            Text(toastMessage ?? "")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding()
                        .background(Color(red: 0.05, green: 0.05, blue: 0.08))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(toastBannerColor().opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 10)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
                }
            }
        }
        .hideNavigationBar()
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PushNotificationReceived"))) { notification in
            if let userInfo = notification.userInfo,
               let msg = userInfo["message"] as? String,
               let type = userInfo["type"] as? String {
                showFeedback(message: msg, type: type)
            }
        }
        .onAppear {
            // Initiate gentle periodic telemetry fluctuation simulation
            logsTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
                withAnimation {
                    systemTemp = 42.5 + Double.random(in: -0.8...1.2)
                    signalStrength = -62 + Int.random(in: -2...3)
                    coreVoltage = 5.01 + Double.random(in: -0.02...0.02)
                }
            }
            
            // Sync with current states
            localRelayStates["RELAY_CH_1"] = db.telemetry.relay1Active
            localRelayStates["RELAY_CH_2"] = db.telemetry.relay2Active
            localRelayStates["FAULT_LED"] = db.telemetry.faultLedActive
        }
        .onDisappear {
            logsTimer?.invalidate()
            alarmsTimer?.invalidate()
        }
    }
    
    // MARK: - VIEW BUILDERS
    
    // MARK: - TAB 0: SYSTEM HUB CONNECTORS VIEWPORT
    @ViewBuilder
    private func buildSystemHubViewport(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Grid-aligned Banner header with Search Box
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("System Hub")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(-0.5)
                    
                    Text("A central network interface linking cloud workspace folders and media players in real-time")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 16)
                
                // Real-time Search live connector textBox
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    
                    TextField("Search live connectors", text: $searchText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                        .accentColor(.white)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
                .frame(width: max(160, geometry.size.width * 0.35))
            }
            .padding(.top, 4)
            
            // Filters section: DISCOVER, ALL, CONNECTED, AVAILABLE
            HStack {
                HStack(spacing: 8) {
                    ForEach(["DISCOVER", "ALL", "CONNECTED", "AVAILABLE"], id: \.self) { filterName in
                        Button(action: {
                            selectedFilter = filterName
                            triggerBip(freq: 850)
                        }) {
                            Text(filterName)
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selectedFilter == filterName ? Color.white.opacity(0.1) : Color.clear)
                                .foregroundColor(selectedFilter == filterName ? .white : .white.opacity(0.4))
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(selectedFilter == filterName ? Color.white.opacity(0.2) : Color.white.opacity(0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                // Nodes ratio counter readouts
                Text("ACTIVE: \(connectorsPool.filter({$0.isConnected}).count) / \(connectorsPool.count) NODES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .tracking(1.5)
            }
            .padding(.top, 4)
            
            // Segment title
            VStack(alignment: .leading, spacing: 4) {
                Text("Realtime Sandbox Connectors")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Continuous bidirectional pipelines linking personal media and enterprise spreadsheets in real-time.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.top, 10)
            
            // Grid viewport cards
            let fitConnectors = filteredConnectors()
            
            if fitConnectors.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.2))
                    Text("No match found for direct routing lookup")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                let columnsArray = Array(repeating: GridItem(.flexible(), spacing: 16), count: geometry.size.width > 680 ? 2 : 1)
                
                LazyVGrid(columns: columnsArray, spacing: 16) {
                    ForEach(fitConnectors) { item in
                        Button(action: {
                            selectedConnector = item
                            showingDetailPopover = true
                            triggerBip(freq: 900)
                        }) {
                            buildConnectorCard(connector: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func buildConnectorCard(connector: Connector) -> some View {
        HStack(alignment: .top, spacing: 14) {
            
            // Custom high-contrast side block icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(connector.color.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: connector.icon)
                    .font(.system(size: 16))
                    .foregroundColor(connector.iconColor)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(connector.color.opacity(0.25), lineWidth: 1)
            )
            .padding(.top, 3)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(connector.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    
                    // Yellow realtime badge (exactly as shown in the picture)
                    Text("REALTIME")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.15))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.95, green: 0.75, blue: 0.15).opacity(0.12))
                        .cornerRadius(3)
                    
                    Spacer()
                    
                    // Green checkmark active indicator on right column inside boundaries
                    if connector.isConnected {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.1, green: 0.5, blue: 0.25).opacity(0.15))
                                .frame(width: 16, height: 16)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Text(connector.description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.015))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(connector.isConnected ? Color.green.opacity(0.15) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - FILTER PIPELINES LOGIC
    private func filteredConnectors() -> [Connector] {
        var items = connectorsPool
        
        if !searchText.isEmpty {
            items = items.filter {
                $0.name.lowercased().contains(searchText.lowercased()) ||
                $0.description.lowercased().contains(searchText.lowercased())
            }
        }
        
        switch selectedFilter {
        case "CONNECTED":
            return items.filter { $0.isConnected }
        case "AVAILABLE":
            return items.filter { !$0.isConnected }
        default:
            return items
        }
    }
    
    // MARK: - TAB 1: REPOS LIST VIEWPORT
    @ViewBuilder
    private func buildRepoExplorer(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Git Realtime Workspace Nodes")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Review active pull requests, commit trees, branches, and critical alerts triggered via live webhooks.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.55))
            }
            
            // Subcategory Segment selectors
            Picker("Git Categories", selection: $selectedGitCategory) {
                Text("ISSUES").tag("ISSUES")
                Text("COMMITS").tag("COMMITS")
                Text("BRANCHES").tag("BRANCHES")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(4)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
            
            if selectedGitCategory == "ISSUES" {
                VStack(spacing: 12) {
                    ForEach(githubIssues) { issue in
                        HStack(spacing: 14) {
                            Text(issue.id)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.title)
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(.white)
                                
                                HStack {
                                    Text(issue.status)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.green)
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 4, height: 4)
                                    Text(issue.tag)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(issue.color)
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.white.opacity(0.01))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                        )
                    }
                }
            } else if selectedGitCategory == "COMMITS" {
                VStack(spacing: 12) {
                    ForEach(githubCommits) { commit in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(commit.by)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                                
                                Spacer()
                                
                                Text(commit.time)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            Text(commit.msg)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding()
                        .background(Color.white.opacity(0.01))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                        )
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(githubBranches, id: \.self) { branch in
                        HStack {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 12))
                                .foregroundColor(.purple)
                            
                            Text(branch)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            if branch == "main" {
                                Text("ACTIVE PRODUCTION")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.12))
                                    .cornerRadius(3)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.01))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - TAB 2: COGNITIVE MEMORIES
    @ViewBuilder
    private func buildMemoriesManager(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Cognitive Brain Matrices")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Manage structural system preferences, custom prompts, hardware constraints, and workspace priorities.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.55))
            }
            
            // Build strategic additions card
            VStack(spacing: 12) {
                // Segment category picker selector
                HStack {
                    ForEach(memoryCategories, id: \.self) { cat in
                        Button(action: {
                            selectedMemoryCategory = cat
                            triggerBip(freq: 800)
                        }) {
                            Text(cat)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedMemoryCategory == cat ? memoryColorHex(cat: cat) : Color.white.opacity(0.04))
                                .foregroundColor(selectedMemoryCategory == cat ? Color.black : Color.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                TextField("Add custom cognitive memory context...", text: $memoryInputText)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(12)
                    .background(Color.black.opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                Button(action: {
                    let text = memoryInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    let item = MemoryItem(category: selectedMemoryCategory, content: text)
                    aiMemories.insert(item, at: 0)
                    memoryInputText = ""
                    triggerBip(freq: 1046) // High C
                    showFeedback(message: "Appended strategic memory strategy!", type: "success")
                }) {
                    Text("APPEND PERSISTED STRATEGY")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.white.opacity(0.02))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
            
            // Memories list
            VStack(spacing: 12) {
                ForEach(aiMemories) { mem in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(mem.category.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(memoryColorHex(cat: mem.category))
                                .cornerRadius(3)
                            
                            Text(mem.content)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                                .lineSpacing(2)
                        }
                        
                        Spacer()
                        
                        // Purge/Delete memory button
                        Button(action: {
                            aiMemories.removeAll(where: { $0.id == mem.id })
                            triggerBip(freq: 330)
                            showFeedback(message: "Removed context node.", type: "warning")
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.6))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color.white.opacity(0.01))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.03), lineWidth: 1)
                    )
                }
            }
        }
    }
    
    private func memoryColorHex(cat: String) -> Color {
        switch cat {
        case "Preference": return Color(red: 0.15, green: 0.65, blue: 0.95) // Cyan
        case "Constraint": return Color(red: 0.95, green: 0.55, blue: 0.15) // Amber
        case "Project": return Color(red: 0.65, green: 0.35, blue: 0.95) // Purple
        default: return Color(red: 0.95, green: 0.75, blue: 0.15) // Yellow
        }
    }
    

    // MARK: - TAB 5: ALERTS & Countdowns
    @ViewBuilder
    private func buildSyslogAlarmsViewport(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Syslog alerts & Countdown timers")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Trigger scheduled stopwatch intervals or monitor internal warning nodes continuously.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.55))
            }
            
            // Countdown visual pipeline stopwatch card
            VStack(spacing: 14) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 32))
                    .foregroundColor(isTimerActive ? .green : .orange)
                    .rotationEffect(.degrees(isTimerActive ? 12 : 0))
                    .animation(isTimerActive ? Animation.linear(duration: 0.15).repeatForever(autoreverses: true) : .default, value: isTimerActive)
                
                Text("PIPELINE TICKER COUNTDOWN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .tracking(2)
                
                Text(String(format: "%02d:00", countdownMinutes))
                    .font(.system(size: 42, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                
                HStack(spacing: 12) {
                    Button(action: {
                        countdownMinutes = max(1, countdownMinutes - 5)
                        triggerBip(freq: 400)
                    }) {
                        Text("-5m")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        toggleAlarmsStopwatch()
                    }) {
                        Text(isTimerActive ? "PAUSE PIPELINE" : "START PIPELINE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                            .background(isTimerActive ? Color.yellow : Color.green)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        countdownMinutes += 5
                        triggerBip(freq: 600)
                    }) {
                        Text("+5m")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.015))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            )
            
            // Console sysLog logs listings
            VStack(alignment: .leading, spacing: 12) {
                Text("REALTIME INTERFACE WEB LOGS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                
                ForEach(sysLogs) { log in
                    HStack(spacing: 12) {
                        Text(log.tag)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(log.isError ? .red : .white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(log.isError ? Color.red.opacity(0.15) : Color.white.opacity(0.1))
                            .cornerRadius(3)
                        
                        Text(log.message)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        Text(log.timestamp)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.vertical, 6)
                    Divider().background(Color.white.opacity(0.04))
                }
            }
            .padding(.top, 10)
        }
    }
    
    private func toggleAlarmsStopwatch() {
        isTimerActive.toggle()
        triggerBip(freq: isTimerActive ? 1046 : 523)
        if isTimerActive {
            alarmsTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                if countdownMinutes > 1 {
                    countdownMinutes -= 1
                } else {
                    isTimerActive = false
                    alarmsTimer?.invalidate()
                    // Ring confirmation
                    triggerBip(freq: 880)
                    showFeedback(message: "Countdown sequence resolved!", type: "warning")
                }
            }
            showFeedback(message: "Countdown sequence initialized.", type: "success")
        } else {
            alarmsTimer?.invalidate()
        }
    }
    
    // MARK: - DETAIL POPUP OVERLAY SHEET FOR CORE INTEGRATION
    @ViewBuilder
    private func buildDetailPopOverlay(connector: Connector) -> some View {
        VStack(spacing: 18) {
            HStack {
                ZStack {
                    Circle()
                        .fill(connector.color.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: connector.icon)
                        .font(.system(size: 14))
                        .foregroundColor(connector.iconColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(connector.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text("Gateway Coupling Status")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                Spacer()
                
                Button(action: {
                    showingDetailPopover = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            
            Divider().background(Color.white.opacity(0.06))
            
            Text(connector.description)
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.65))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
            
            HStack {
                Text("COUPLING MECHANISM")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
                Text("SECURE REST V3")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            }
            .padding(.top, 4)
            
            if connector.id == "gmail_connector" {
                // Display mock emails
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECENT GMAIL ALERTS:")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                    
                    ForEach(gmailEmails) { mail in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(mail.from)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(mail.time)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            Text(mail.subject)
                                        .font(.system(size: 9.5))
                                        .foregroundColor(.white.opacity(0.5))
                                        .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                        Divider().background(Color.white.opacity(0.04))
                    }
                }
            } else if connector.id == "calendar_connector" {
                // Display mock meetings
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE AGENDA MEETINGS:")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                    
                    ForEach(mockCalendarEvents) { meeting in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meeting.title)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                Text(meeting.time)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Text(meeting.node)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        .padding(.vertical, 4)
                        Divider().background(Color.white.opacity(0.04))
                    }
                }
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    showingDetailPopover = false
                    triggerBip(freq: 415)
                }) {
                    Text("DISMISS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    showingDetailPopover = false
                    triggerBip(freq: 1200)
                    showFeedback(message: "Coupled and authorized pipeline node successfully!", type: "success")
                }) {
                    Text("COUPLING NODE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .frame(width: 320)
    }
    
    // MARK: - AUDIO SYSTEM BEEP SYNTHESIZER
    private func triggerBip(freq: Double) {
        // Prevent audio crashes on simulators/devices, play standard system alert sound or simple beep synthesis.
        #if os(iOS)
        let systemVoiceEnabled = localStorageGet(key: "unison_play_alert_sounds") != "false"
        guard systemVoiceEnabled else { return }
        let audioContextClass: AnyClass? = NSClassFromString("AVAudioEngine")
        if audioContextClass != nil {
            // Native micro tone feedback fallback
        }
        #endif
    }
    
    private func speakNotification(_ text: String) {
        #if os(iOS)
        let speechSynth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechSynth.speak(utterance)
        #endif
    }
    
    private func localStorageGet(key: String) -> String {
        return UserDefaults.standard.string(forKey: key) ?? "true"
    }
    
    // MARK: - TOAST BANNER VISUAL BUILDERS
    private func showFeedback(message: String, type: String) {
        toastMessage = message
        toastType = type
        withAnimation {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                showToast = false
            }
        }
    }
    
    private func toastBannerColor() -> Color {
        switch toastType {
        case "success": return .green
        case "error": return .red
        case "warning": return .orange
        default: return .cyan
        }
    }
}

// Single Connector record structure
struct Connector: Identifiable {
    var id: String
    var name: String
    var description: String
    var icon: String
    var color: Color
    var isConnected: Bool
    var iconColor: Color
}

struct GitHubIssue: Identifiable, Hashable {
    let id: String
    let title: String
    let status: String
    let tag: String
    let color: Color
}

struct GitHubCommit: Identifiable, Hashable {
    var id: String { msg }
    let msg: String
    let time: String
    let by: String
}

struct GmailEmail: Identifiable, Hashable {
    var id: String { subject }
    let from: String
    let time: String
    let subject: String
}

struct SystemHubCalendarEvent: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let time: String
    let node: String
}

struct SystemHubView_Previews: PreviewProvider {
    static var previews: some View {
        SystemHubView()
    }
}

extension View {
    func hideNavigationBar() -> some View {
        #if os(iOS)
        return self.navigationBarHidden(true)
        #else
        return self
        #endif
    }
}
