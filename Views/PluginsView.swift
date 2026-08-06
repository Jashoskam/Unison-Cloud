import SwiftUI

public enum CommandActionType: String, CaseIterable, Identifiable {
    case click = "Left Click"
    case rightClick = "Right Click"
    case doubleClick = "Double Click"
    case hover = "Hover Cursor"
    case typeText = "Type Text"
    case keyCombo = "Key Combo"
    case scrollUp = "Scroll Up"
    case scrollDown = "Scroll Down"
    
    public var id: String { rawValue }
    
    public var symbol: String {
        switch self {
        case .click: return "hand.tap.fill"
        case .rightClick: return "contextualmenu.and.cursor"
        case .doubleClick: return "hand.tap"
        case .hover: return "arrow.up.and.down.and.arrow.left.and.right"
        case .typeText: return "keyboard"
        case .keyCombo: return "command"
        case .scrollUp: return "arrow.up.circle.fill"
        case .scrollDown: return "arrow.down.circle.fill"
        }
    }
}

public struct PluginsView: View {
    @Binding var isSidebarExpanded: Bool
    var onLaunchComputerUse: () -> Void
    
    @StateObject private var overlayService = SystemOverlayService.shared
    @StateObject private var agentController = AgentStateController.shared
    @StateObject private var cursorManager = VirtualCursorManager.shared
    
    @State private var searchQuery = ""
    @State private var showingComputerUseDetail = false
    
    // Command Generator State
    @State private var targetX: String = "500"
    @State private var targetY: String = "500"
    @State private var selectedActionType: CommandActionType = .click
    @State private var textPayload: String = ""
    @State private var scrollDelta: String = "10"
    @State private var executionStatusMessage: String = "Ready to generate screen-coordinate commands"
    @State private var agentObjectiveText: String = "Open Calculator, click 7, and type 42"
    
    public init(isSidebarExpanded: Binding<Bool> = .constant(true), onLaunchComputerUse: @escaping () -> Void) {
        self._isSidebarExpanded = isSidebarExpanded
        self.onLaunchComputerUse = onLaunchComputerUse
    }
    
    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.05)
                .ignoresSafeArea()
            
            if showingComputerUseDetail {
                computerUseDetailView
                    .transition(.move(edge: .trailing))
            } else {
                mainPluginsStoreView
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingComputerUseDetail)
    }
    
    @ViewBuilder
    private var mainPluginsStoreView: some View {
        VStack(spacing: 0) {
            // Top Nav Bar
            HStack {
                HStack(spacing: 12) {
                    if !isSidebarExpanded {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isSidebarExpanded.toggle()
                            }
                        }) {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {}) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {}) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {}) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        
                        Spacer().frame(width: 8)
                    }
                    
                    Text("Plugins")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(8)
                    
                    Text("Skills")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: {}) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {}) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {}) {
                        HStack(spacing: 4) {
                            Text("Create")
                                .font(.system(size: 12, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 6)
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            ScrollView {
                HStack {
                    Spacer(minLength: 16)
                    
                    VStack(alignment: .leading, spacing: 22) {
                        // Header Area
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Plugins")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                            Text("Work with ChatGPT across your favorite tools")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.top, 16)
                        
                        // Search plugins
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.4))
                            TextField("Search plugins", text: $searchQuery)
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                                .font(.system(size: 14))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                )
                        )
                        
                        // Installed section
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Installed")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: {}) {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            
                            HStack(spacing: 12) {
                                PluginIconView(color: Color(red: 0.1, green: 0.5, blue: 0.95), symbol: "doc.text.fill")
                                PluginIconView(color: Color(red: 0.9, green: 0.25, blue: 0.25), symbol: "pdf")
                                PluginIconView(color: Color(red: 0.15, green: 0.65, blue: 0.35), symbol: "tablecells.fill")
                                PluginIconView(color: Color(red: 0.9, green: 0.6, blue: 0.1), symbol: "play.rectangle.fill")
                                PluginIconView(color: Color(red: 0.2, green: 0.55, blue: 0.8), symbol: "square.stack.3d.up.fill")
                                
                                Button(action: {
                                    showingComputerUseDetail = true
                                }) {
                                    PluginIconView(gradient: true)
                                }
                                .buttonStyle(.plain)
                                
                                PluginIconView(color: Color(red: 0.2, green: 0.65, blue: 0.95), symbol: "sparkles")
                            }
                        }
                        .padding(.top, 4)
                        
                        // Filter Pills (Public / Personal)
                        HStack {
                            HStack(spacing: 0) {
                                Text("Public")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(8)
                                
                                Text("Personal")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                            }
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(10)
                            
                            Spacer()
                            
                            Button(action: {}) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Featured Section
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Featured")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                                // 1. Computer Use
                                Button(action: {
                                    showingComputerUseDetail = true
                                }) {
                                    HStack(spacing: 12) {
                                        PluginIconView(gradient: true)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Computer Use")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                            Text("Control Mac apps from ChatGPT")
                                                .font(.system(size: 11))
                                                .foregroundColor(.white.opacity(0.5))
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.03))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                pluginCard(title: "Gmail Plugin", subtitle: "List, read threads & compose emails", isInstalled: true, symbol: "envelope.badge.shield.half.filled", color: Color(red: 0.9, green: 0.2, blue: 0.2))
                                pluginCard(title: "Scheduled Tasks Engine", subtitle: "Automated background cron agents", isInstalled: true, symbol: "clock.badge.checkmark", color: Color(red: 0.5, green: 0.2, blue: 0.9))
                                pluginCard(title: "Code Interpreter", subtitle: "Sandboxed Python & JS evaluation", isInstalled: true, symbol: "terminal.fill", color: Color(red: 0.15, green: 0.65, blue: 0.35))
                                pluginCard(title: "Memory Knowledge Graph", subtitle: "Persistent long-term concept memory", isInstalled: true, symbol: "brain.head.profile", color: Color(red: 0.1, green: 0.6, blue: 0.9))
                                pluginCard(title: "Web Search & Browser", subtitle: "Real-time web search & page extraction", isInstalled: true, symbol: "safari.fill", color: Color(red: 0.2, green: 0.5, blue: 0.95))
                                pluginCard(title: "Google Workspace", subtitle: "Calendar, Drive & Docs integration", isInstalled: true, symbol: "doc.text.fill", color: Color(red: 0.95, green: 0.6, blue: 0.1))
                            }
                        }
                        
                        // Productivity Grid
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Productivity & Enterprise Modules")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                                pluginCard(title: "Notion", subtitle: "Sync notes and database pages", isInstalled: false, symbol: "doc.text.magnifyingglass", color: Color(red: 0.2, green: 0.2, blue: 0.22))
                                pluginCard(title: "Zoom", subtitle: "Manage meetings and transcripts", isInstalled: false, symbol: "video.fill", color: Color(red: 0.1, green: 0.5, blue: 0.95))
                            }
                        }
                        .padding(.bottom, 60)
                    }
                    .frame(maxWidth: 720)
                    
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    @ViewBuilder
    private var computerUseDetailView: some View {
        VStack(spacing: 0) {
            // Header Nav
            HStack {
                Button(action: {
                    showingComputerUseDetail = false
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back to Plugins")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                HStack(spacing: 10) {
                    Circle()
                        .fill(agentController.isLoopRunning ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("Agent: \(agentController.state.rawValue)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 2)
            .padding(.bottom, 8)
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Profile Block
                    HStack(spacing: 16) {
                        PluginIconView(gradient: true)
                            .scaleEffect(1.4)
                            .frame(width: 48, height: 48)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text("Computer Use")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)
                                Text("v2.4")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            Text("Screen-coordinate generation, accessibility context & event injection hooks")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Text("Active Architecture")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    // 1. Accessibility Context & System Permissions Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "accessibility")
                                .font(.system(size: 14))
                                .foregroundColor(.cyan)
                            Text("Desktop Accessibility Context")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: {
                                overlayService.refreshAccessibilityContext()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Refresh Context")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.cyan.opacity(0.12))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                            GridRow {
                                Text("Active Application:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                                Text(overlayService.activeApplicationName)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            GridRow {
                                Text("Window Title:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                                Text(overlayService.activeWindowTitle.isEmpty ? "No Window Selected" : overlayService.activeWindowTitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(1)
                            }
                            if !overlayService.selectedText.isEmpty {
                                GridRow {
                                    Text("Focused Text:")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.gray)
                                    Text(overlayService.selectedText)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.cyan)
                                        .lineLimit(2)
                                }
                            }
                        }
                        
                        if !overlayService.accessibilitySummary.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AX UI Tree Summary:")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.gray)
                                Text(overlayService.accessibilitySummary)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.75))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(6)
                            }
                        }
                        
                        // Permissions status badges
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: TCCPermissionChecker.verifyAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(TCCPermissionChecker.verifyAccessibility ? .green : .orange)
                                Text("AX Permission: \(TCCPermissionChecker.verifyAccessibility ? "Granted" : "Required")")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            HStack(spacing: 6) {
                                Image(systemName: TCCPermissionChecker.verifyScreenCapture ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(TCCPermissionChecker.verifyScreenCapture ? .green : .orange)
                                Text("Screen Capture: \(TCCPermissionChecker.verifyScreenCapture ? "Granted" : "Required")")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    
                    // 2. Screen-Coordinate Command Generator & Injection Console
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "crosshair")
                                .font(.system(size: 14))
                                .foregroundColor(.cyan)
                            Text("Screen-Coordinate Command Generator & Injector")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Generate precise screen coordinates (0-1000 scale) and synthesize hardware HID mouse, keyboard, or scroll events via native accessibility injection hooks.")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        
                        // Coordinate Inputs & Action Selector
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Coordinate X (0-1000)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.gray)
                                    TextField("X", text: $targetX)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.06))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Coordinate Y (0-1000)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.gray)
                                    TextField("Y", text: $targetY)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.06))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Scroll Delta / Lines")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.gray)
                                    TextField("Delta", text: $scrollDelta)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.06))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            // Action Type Grid / Segment
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Synthesizer Action Type:")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.gray)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(CommandActionType.allCases) { actionType in
                                            Button(action: {
                                                selectedActionType = actionType
                                            }) {
                                                HStack(spacing: 5) {
                                                    Image(systemName: actionType.symbol)
                                                        .font(.system(size: 11))
                                                    Text(actionType.rawValue)
                                                        .font(.system(size: 11, weight: .semibold))
                                                }
                                                .foregroundColor(selectedActionType == actionType ? .black : .white.opacity(0.8))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background(selectedActionType == actionType ? Color.white : Color.white.opacity(0.08))
                                                .cornerRadius(8)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            
                            if selectedActionType == .typeText || selectedActionType == .keyCombo {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedActionType == .typeText ? "Text Payload to Type:" : "Key Combination (e.g. 'cmd+space', 'enter'):")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.gray)
                                    TextField("Payload", text: $textPayload)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 12, design: .monospaced))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.06))
                                        .cornerRadius(8)
                                        .foregroundColor(.cyan)
                                }
                            }
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    executeGeneratedCoordinateCommand()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "bolt.fill")
                                        Text("Execute Coordinate Action")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(Color.cyan)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: {
                                    cursorManager.isVisible = true
                                    let center = CGPoint(x: 500, y: 500)
                                    let screenPoint = CoordinateMapper.translateNormalizedToScreen(normalizedX: center.x, normalizedY: center.y)
                                    cursorManager.animateTo(targetPoint: screenPoint)
                                    executionStatusMessage = "Pulsed virtual overlay cursor at center [500, 500]"
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "scope")
                                        Text("Pulse Pointer Overlay")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Text(executionStatusMessage)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.cyan.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(6)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    
                    // 3. Closed-Loop Agent Perception & Control Loop
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "cpu")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                            Text("Closed-Loop Autonomous Agent Loop")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Text(agentController.state.rawValue)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(agentController.isLoopRunning ? .green : .gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(agentController.isLoopRunning ? Color.green.opacity(0.15) : Color.white.opacity(0.05))
                                .cornerRadius(6)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Agent Task Objective:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.gray)
                            TextField("Objective", text: $agentObjectiveText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                agentController.agentQuery = agentObjectiveText
                                agentController.startLoop()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                    Text("Start Autonomous Agent")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.green)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(agentController.isLoopRunning)
                            
                            Button(action: {
                                agentController.stopLoop()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "stop.fill")
                                    Text("Stop Agent")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                onLaunchComputerUse()
                                showingComputerUseDetail = false
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.stack.3d.up.fill")
                                    Text("Launch Notes Preset")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    
                    // 4. Execution Stream & Logs
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            Text("Realtime Agent Perception Stream & Event Logs")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(agentController.logs.count) events")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                if agentController.logs.isEmpty {
                                    Text("No execution events recorded yet.")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.gray)
                                } else {
                                    ForEach(agentController.logs.prefix(25), id: \.self) { logLine in
                                        Text(logLine)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(logLine.contains("ERROR") ? .red : (logLine.contains("Success") ? .green : .white.opacity(0.8)))
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 140)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 20)
            }
        }
    }
    
    private func executeGeneratedCoordinateCommand() {
        guard let x = Double(targetX), let y = Double(targetY) else {
            executionStatusMessage = "Invalid coordinates. Range must be 0 - 1000."
            return
        }
        
        executionStatusMessage = "Translating [\(targetX), \(targetY)] to screen coordinates..."
        let screenPoint = CoordinateMapper.translateNormalizedToScreen(normalizedX: x, normalizedY: y)
        
        cursorManager.isVisible = true
        cursorManager.currentActionStatus = selectedActionType.rawValue
        cursorManager.animateTo(targetPoint: screenPoint)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            cursorManager.isClicking = true
            
            switch selectedActionType {
            case .click:
                let axSuccess = EventSynthesizer.shared.performAccessibilityAction(at: screenPoint)
                if !axSuccess {
                    EventSynthesizer.shared.postClick(at: screenPoint, button: .left)
                }
                executionStatusMessage = "Executed Left Click at screen point (\(Int(screenPoint.x)), \(Int(screenPoint.y)))"
                
            case .rightClick:
                EventSynthesizer.shared.postClick(at: screenPoint, button: .right)
                executionStatusMessage = "Executed Right Click at screen point (\(Int(screenPoint.x)), \(Int(screenPoint.y)))"
                
            case .doubleClick:
                EventSynthesizer.shared.postDoubleClick(at: screenPoint)
                executionStatusMessage = "Executed Double Click at screen point (\(Int(screenPoint.x)), \(Int(screenPoint.y)))"
                
            case .hover:
                EventSynthesizer.shared.postHover(at: screenPoint)
                executionStatusMessage = "Hovered pointer at screen point (\(Int(screenPoint.x)), \(Int(screenPoint.y)))"
                
            case .typeText:
                if !textPayload.isEmpty {
                    EventSynthesizer.shared.postKeyboardEvent(string: textPayload)
                    executionStatusMessage = "Typed '\(textPayload)' into active focus target"
                } else {
                    executionStatusMessage = "Provide text payload to synthesize typing"
                }
                
            case .keyCombo:
                if !textPayload.isEmpty {
                    EventSynthesizer.shared.postKeyCombo(textPayload)
                    executionStatusMessage = "Executed key combo '\(textPayload)'"
                } else {
                    executionStatusMessage = "Provide key combo payload (e.g. 'cmd+space')"
                }
                
            case .scrollUp:
                let delta = Int32(scrollDelta) ?? 10
                EventSynthesizer.shared.postScroll(at: screenPoint, deltaY: delta)
                executionStatusMessage = "Scrolled Up \(delta) lines at (\(Int(screenPoint.x)), \(Int(screenPoint.y)))"
                
            case .scrollDown:
                let delta = Int32(scrollDelta) ?? 10
                EventSynthesizer.shared.postScroll(at: screenPoint, deltaY: -delta)
                executionStatusMessage = "Scrolled Down \(delta) lines at (\(Int(screenPoint.x)), \(Int(screenPoint.y)))"
            }
            
            agentController.log("PluginsUI Command Injector: \(executionStatusMessage)")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                cursorManager.isClicking = false
            }
        }
    }
    
    @ViewBuilder
    private func pluginCard(title: String, subtitle: String, isInstalled: Bool, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            PluginIconView(color: color, symbol: symbol)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isInstalled {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("Install")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// Icon renderer
struct PluginIconView: View {
    var color: Color = .gray
    var symbol: String = ""
    var gradient = false
    
    var body: some View {
        ZStack {
            if gradient {
                LinearGradient(
                    colors: [Color(red: 0.1, green: 0.45, blue: 0.95), Color(red: 0.85, green: 0.25, blue: 0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                color
            }
            
            if symbol == "pdf" {
                Text("PDF")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white)
            } else if gradient {
                Image(systemName: "location.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .rotationEffect(.init(degrees: -45))
                    .offset(x: -1, y: 1)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 32, height: 32)
        .cornerRadius(8)
    }
}
