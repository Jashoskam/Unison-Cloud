import SwiftUI

public struct SettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject var db: FirestoreService = FirestoreService.shared
    
    @State private var selectedTab: SettingsTab = .general
    @State private var searchQuery: String = ""
    
    // Settings States
    @State private var defaultPermissions: Bool = true
    @State private var fullAccess: Bool = false
    @State private var selectedEditor: String = "VS Code"
    @State private var selectedLanguage: String = "Auto detect"
    @State private var showInMenuBar: Bool = true
    @State private var bottomPanel: Bool = false
    @State private var preventSleep: Bool = false
    @State private var showLicensesModal: Bool = false
    
    // Additional settings state
    @State private var selectedTheme: String = "Dark"
    @State private var voiceEngine: String = "Juniper"
    @State private var computerUseEnabled: Bool = true
    @State private var gitAutoCommit: Bool = false
    
    public enum SettingsTab: String, CaseIterable, Identifiable {
        // Personal
        case general = "General"
        case importData = "Import"
        case profile = "Profile"
        case appearance = "Appearance"
        case voice = "Voice"
        case configuration = "Configuration"
        case personalization = "Personalization"
        case pets = "Pets"
        case keyboardShortcuts = "Keyboard shortcuts"
        case usageBilling = "Usage & billing"
        case account = "Account"
        
        // Integrations
        case appshots = "Appshots"
        case plugins = "Plugins"
        case scheduledTasks = "Scheduled tasks"
        case browser = "Browser"
        case computerUse = "Computer use"
        
        // Coding
        case hooks = "Hooks"
        case connections = "Connections"
        case git = "Git"
        
        public var id: String { self.rawValue }
        
        public var iconName: String {
            switch self {
            case .general: return "gearshape"
            case .importData: return "square.and.arrow.down"
            case .profile: return "person.crop.circle"
            case .appearance: return "sun.max"
            case .voice: return "mic"
            case .configuration: return "slider.horizontal.3"
            case .personalization: return "dial.low"
            case .pets: return "pawprint"
            case .keyboardShortcuts: return "keyboard"
            case .usageBilling: return "chart.line.uptrend.xyaxis"
            case .account: return "globe"
            case .appshots: return "viewfinder"
            case .plugins: return "puzzlepiece"
            case .scheduledTasks: return "clock"
            case .browser: return "macwindow"
            case .computerUse: return "sparkles"
            case .hooks: return "anchor"
            case .connections: return "network"
            case .git: return "arrow.triangle.pull"
            }
        }
        
        public var section: String {
            switch self {
            case .general, .importData, .profile, .appearance, .voice, .configuration, .personalization, .pets, .keyboardShortcuts, .usageBilling, .account:
                return "Personal"
            case .appshots, .plugins, .scheduledTasks, .browser, .computerUse:
                return "Integrations"
            case .hooks, .connections, .git:
                return "Coding"
            }
        }
    }
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            sidebarView
                .frame(width: 240)
                .background(Color(red: 0.12, green: 0.12, blue: 0.125))
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // Right Main Settings Area
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.09, green: 0.09, blue: 0.095))
        }
        .foregroundColor(.white)
        .font(.system(size: 13))
        .sheet(isPresented: $showLicensesModal) {
            licensesModalView
        }
    }
    
    // MARK: - Sidebar View
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Back Button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isPresented = false
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 13, weight: .medium))
                    Text("Back to app")
                        .font(.system(size: 13, weight: .regular))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .buttonStyle(.plain)
            
            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                
                TextField("Search settings...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            
            // Navigation Categories List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    sidebarSection(title: "Personal", tabs: [.general, .importData, .profile, .appearance, .voice, .configuration, .personalization, .pets, .keyboardShortcuts, .usageBilling, .account])
                    
                    sidebarSection(title: "Integrations", tabs: [.appshots, .plugins, .browser, .computerUse])
                    
                    sidebarSection(title: "Coding", tabs: [.hooks, .connections, .git])
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
    }
    
    @ViewBuilder
    private func sidebarSection(title: String, tabs: [SettingsTab]) -> some View {
        let filtered = tabs.filter { tab in
            searchQuery.isEmpty || tab.rawValue.localizedCaseInsensitiveContains(searchQuery)
        }
        
        if !filtered.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.38))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                
                ForEach(filtered) { tab in
                    let isSelected = selectedTab == tab
                    Button(action: {
                        selectedTab = tab
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 13, weight: .regular))
                                .frame(width: 16, alignment: .center)
                                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                            
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.85))
                            
                            Spacer()
                            
                            if tab == .account {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.35))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color(red: 0.22, green: 0.22, blue: 0.23) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Main Content Area
    private var mainContentArea: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                // Header Title
                Text(selectedTab.rawValue)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 8)
                
                switch selectedTab {
                case .general:
                    generalSettingsContent
                case .importData:
                    importSettingsContent
                case .profile:
                    profileSettingsContent
                case .appearance:
                    appearanceSettingsContent
                case .voice:
                    voiceSettingsContent
                case .configuration:
                    configurationSettingsContent
                case .scheduledTasks:
                    scheduledTasksSettingsContent
                case .computerUse:
                    computerUseSettingsContent
                case .git:
                    gitSettingsContent
                default:
                    genericTabContent(tabName: selectedTab.rawValue)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .padding(.bottom, 48)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
    
    // MARK: - General Settings Content (Pixel Perfect to Image)
    private var generalSettingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Permissions Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                VStack(spacing: 0) {
                    // Row 1: Default permissions
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Default permissions")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("By default, ChatGPT can read and edit files in its workspace. It can ask for additional access when needed")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $defaultPermissions)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                    }
                    .padding(16)
                    
                    Divider()
                        .background(Color.white.opacity(0.08))
                    
                    // Row 2: Full access
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Full access")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            
                            (Text("When ChatGPT runs with full access, it can edit any file on your computer and run commands with network, without your approval. This significantly increases the risk of data loss, leaks, or unexpected behavior. ")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55)) +
                             Text("Learn more")
                                .font(.system(size: 12))
                                .foregroundColor(.blue) +
                             Text(" about elevated risks."))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $fullAccess)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                    }
                    .padding(16)
                }
                .background(Color(red: 0.137, green: 0.137, blue: 0.145))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            
            // General Options Section
            VStack(alignment: .leading, spacing: 10) {
                Text("General")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                VStack(spacing: 0) {
                    // Row 1: Default file open destination
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Default file open destination")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("Where files and folders open by default")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        
                        Spacer()
                        
                        Menu {
                            Button("VS Code") { selectedEditor = "VS Code" }
                            Button("Xcode") { selectedEditor = "Xcode" }
                            Button("Finder") { selectedEditor = "Finder" }
                            Button("Terminal") { selectedEditor = "Terminal" }
                        } label: {
                            HStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.blue)
                                        .frame(width: 14, height: 14)
                                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                Text(selectedEditor)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                        }
                        .menuStyle(.borderlessButton)
                    }
                    .padding(16)
                    
                    Divider().background(Color.white.opacity(0.08))
                    
                    // Row 2: Language
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Language")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("Language for the app UI")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        
                        Spacer()
                        
                        Menu {
                            Button("Auto detect") { selectedLanguage = "Auto detect" }
                            Button("English") { selectedLanguage = "English" }
                            Button("Spanish") { selectedLanguage = "Spanish" }
                            Button("French") { selectedLanguage = "French" }
                            Button("German") { selectedLanguage = "German" }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedLanguage)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                        }
                        .menuStyle(.borderlessButton)
                    }
                    .padding(16)
                    
                    Divider().background(Color.white.opacity(0.08))
                    
                    // Row 3: Show in menu bar
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Show in menu bar")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("Keep ChatGPT in the macOS menu bar when the main window is closed")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $showInMenuBar)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                    }
                    .padding(16)
                    
                    Divider().background(Color.white.opacity(0.08))
                    
                    // Row 4: Bottom panel
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bottom panel")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("Show the bottom panel control in the app header")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $bottomPanel)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                    }
                    .padding(16)
                    
                    Divider().background(Color.white.opacity(0.08))
                    
                    // Row 5: Prevent sleep while running
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Prevent sleep while running")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("Keep your computer awake while ChatGPT is running a task")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $preventSleep)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                    }
                    .padding(16)
                    
                    Divider().background(Color.white.opacity(0.08))
                    
                    // Row 6: Open source licenses
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Open source licenses")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("Third-party notices for bundled dependencies")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            showLicensesModal = true
                        }) {
                            Text("View")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
                .background(Color(red: 0.137, green: 0.137, blue: 0.145))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Secondary Settings Sections
    private var importSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Data & History")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Import previous chat archives or local markdown workspaces directly into your UNISON database.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                
                Button(action: {}) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Choose Zip or JSON file...")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(red: 0.137, green: 0.137, blue: 0.145))
            .cornerRadius(12)
        }
    }
    
    private var profileSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("User Account Profile")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 44, height: 44)
                        .overlay(Text("JA").font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jash Oskam")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text("jashoskam@gmail.com")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding(16)
            .background(Color(red: 0.137, green: 0.137, blue: 0.145))
            .cornerRadius(12)
        }
    }
    
    private var appearanceSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Theme & Visual Design")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            VStack(alignment: .leading, spacing: 12) {
                Picker("Theme Mode", selection: $selectedTheme) {
                    Text("Dark").tag("Dark")
                    Text("System").tag("System")
                    Text("Light").tag("Light")
                }
                .pickerStyle(.segmented)
            }
            .padding(16)
            .background(Color(red: 0.137, green: 0.137, blue: 0.145))
            .cornerRadius(12)
        }
    }
    
    private var voiceSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Native Voice Synthesizer")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Select active voice for continuous real-time audio interaction.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(16)
            .background(Color(red: 0.137, green: 0.137, blue: 0.145))
            .cornerRadius(12)
        }
    }
    
    private var computerUseSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Computer Use HUD & HID Injections")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable CGEvent Native Mouse Control")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Allows agent to dispatch native clicks via CGEvent injection")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                    Toggle("", isOn: $computerUseEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                }
                
                Divider().background(Color.white.opacity(0.08))
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Autonomous Computer Use Demo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Launches Apple Notes, creates a new note (Cmd+N), and types a note autonomously")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                    
                    Button(action: {
                        isPresented = false
                        #if os(macOS)
                        FirestoreService.shared.openNotesAndTypeNoteDemo()
                        #endif
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.pencil")
                            Text("Run Notes Demo")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.cyan.opacity(0.8))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(Color(red: 0.137, green: 0.137, blue: 0.145))
            .cornerRadius(12)
        }
    }
    
    private var gitSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Git & Workspace Control")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-commit workspace steps")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Automatically stage and commit file modifications")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                    Toggle("", isOn: $gitAutoCommit)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                }
            }
            .padding(16)
            .background(Color(red: 0.137, green: 0.137, blue: 0.145))
            .cornerRadius(12)
        }
    }

    private var configurationSettingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Raspberry Pi Centralized Brain Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.green)
                    Text("Raspberry Pi Centralized Brain")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(db.piBrainIsConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(db.piBrainIsConnected ? "Brain Connected" : "Disconnected")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(db.piBrainIsConnected ? .green : .red)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(12)
                }
                
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Neural Brain Server URL / IP")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(.white)
                            Text("Set your Raspberry Pi IP or local address (e.g. http://192.168.1.100:3000)")
                                .font(.system(size: 11.5))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Spacer()
                    }
                    
                    HStack(spacing: 8) {
                        TextField("http://unison-brain.local:3000", text: $db.raspberryPiBrainUrl)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color(white: 0.08))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        
                        Button(action: {
                            db.fetchRaspberryPiBrainStatus()
                        }) {
                            Text("Ping Pi")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.green)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if db.piBrainIsConnected {
                        HStack(spacing: 16) {
                            if let temp = db.piBrainCpuTemp {
                                HStack(spacing: 4) {
                                    Image(systemName: "thermometer")
                                        .foregroundColor(.orange)
                                    Text("Pi Temp: \(String(format: "%.1f", temp))°C")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                            
                            HStack(spacing: 4) {
                                Image(systemName: "network")
                                    .foregroundColor(.cyan)
                                Text("Mesh Nodes: \(db.piBrainActiveClients)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .background(Color(red: 0.137, green: 0.137, blue: 0.145))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
    }
    
    private var scheduledTasksSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Background Agent Engine & Scheduled Tasks")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Render Background Service Endpoint")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("http://localhost:3000/api/v1/scheduled-tasks")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    Spacer()
                    Text("ONLINE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                }
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Memory Limit & Concurrency Guardrails")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack {
                        Text("Render Free Tier RAM Cap:")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Text("400 MB (--max-old-space-size=400)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    HStack {
                        Text("Task Timeout Threshold:")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Text("30 seconds max per run")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .padding(16)
            .background(Color(red: 0.137, green: 0.137, blue: 0.145))
            .cornerRadius(12)
        }
    }
    
    private func genericTabContent(tabName: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(tabName) Configuration")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Configure settings and defaults for \(tabName.lowercased()).")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(16)
            .background(Color(red: 0.137, green: 0.137, blue: 0.145))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Open Source Licenses Modal
    private var licensesModalView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Open Source Licenses")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button("Close") {
                    showLicensesModal = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("UNISON Companion utilizes open-source components under MIT and Apache 2.0 licenses, including SwiftUI, Google GenAI SDK, and Apple Accessibility APIs.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(24)
        .frame(width: 480, height: 320)
        .background(Color(red: 0.14, green: 0.14, blue: 0.15))
    }
}
