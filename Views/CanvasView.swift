import SwiftUI
import Combine

// --- SIMULATED JUPYTER CELL MODEL ---
struct JupyterCell: Identifiable {
    let id = UUID()
    var code: String
    var output: String
    var isRunning: Bool = false
    var hasRun: Bool = false
}

public struct CanvasView: View {
    @ObservedObject var db = FirestoreService.shared
    
    let isMobile: Bool
    
    // --- CANVAS STATES ---
    @State private var selectedCanvasElementId: String? = nil
    @State private var canvasBrowserUrl: String = "https://ocw.mit.edu"
    @State private var isBrowserLoading: Bool = false
    @State private var documentTitle: String = "test"
    @State private var isStarred: Bool = true
    @State private var saveStatus: String = "Synced"
    @State private var zoomPercent: Int = 100
    @State private var showSettingsPopover: Bool = false
    
    // --- COMPUTED TAB STYLING PROPERTIES ---
    private var documentTabBg: Color {
        selectedMode == "Document" ? Color.white.opacity(0.08) : Color.clear
    }
    private var documentTabFg: Color {
        selectedMode == "Document" ? Color.blue : Color.gray
    }
    private var jupyterTabBg: Color {
        selectedMode == "Jupyter" ? Color.white.opacity(0.08) : Color.clear
    }
    private var jupyterTabFg: Color {
        selectedMode == "Jupyter" ? Color.orange : Color.gray
    }
    private var aiChatTabBg: Color {
        selectedMode == "AI Chat" ? Color.white.opacity(0.08) : Color.clear
    }
    private var aiChatTabFg: Color {
        selectedMode == "AI Chat" ? Color.purple : Color.gray
    }
    
    // --- DROPDOWN MENUS ---
    @State private var activeMenu: String? = nil
    
    // --- TOOLBAR SELECTIONS ---
    @State private var selectedFont: String = "Arial"
    @State private var selectedStyle: String = "Normal Text"
    @State private var selectedSize: Int = 14
    @State private var isBold: Bool = false
    @State private var isItalic: Bool = false
    @State private var isUnderline: Bool = false
    @State private var selectedColorHex: String = "#FFFFFF"
    @State private var selectedHighlightHex: String = "#000000"
    @State private var textAlignment: String = "Left"
    
    // --- POPUP DIALOGS ---
    @State private var showColorDropdown: Bool = false
    @State private var showHighlightDropdown: Bool = false
    @State private var showFontDropdown: Bool = false
    @State private var showStyleDropdown: Bool = false
    @State private var showZoomDropdown: Bool = false
    
    // --- SIDEBAR COLLAPSES ---
    @State private var isOutlineOpen: Bool = false
    @State private var isUnisonAiOpen: Bool = false
    @State private var aiInputMessage: String = ""
    @State private var aiMessages: [ChatMessage] = []
    @State private var isAiThinking: Bool = false
    
    // --- AI CODE CHAT MODE STATES ---
    @State private var codeChatMessages: [ChatMessage] = [
        ChatMessage(role: "model", content: "Welcome to AI Code Studio. Ask me to generate code scripts or programs, and I will write them for you to review and run in the local environment.")
    ]
    @State private var codeChatInput: String = ""
    @State private var isCodeChatThinking: Bool = false
    @State private var activeCodeFile: String = "script.py"
    @State private var activeCodeContent: String = """
# Python Math & System Validation Script
import sys
import os

def check_system():
    print("Initializing local validation...")
    print(f"Python Version: {sys.version}")
    print(f"Target Directory: {os.getcwd()}")
    print("Verification Successful!")

if __name__ == "__main__":
    check_system()
"""
    @State private var codeExecutionOutput: String = ""
    @State private var isCodeRunning: Bool = false
    
    // --- MODE & SPLIT STATES ---
    @State private var selectedMode: String = "Document" // "Document" or "Jupyter"
    @State private var splitMode: String = "Standard Split" // "Standard Split" or "Full Canvas" or "Full Browser"
    
    // --- UNDO / REDO SYSTEM HISTORY ---
    @State private var canvasHistory: [[CanvasElement]] = []
    @State private var redoHistory: [[CanvasElement]] = []
    
    // --- JUPYTER SIMULATION STATE ---
    @State private var jupyterCells: [JupyterCell] = [
        JupyterCell(code: "import unison_core as uc\nuc.verify_asymptotic_constraints()", output: ""),
        JupyterCell(code: "uc.execute_spatial_boundary_analysis(lat=26.14, lon=91.73)", output: ""),
        JupyterCell(code: "uc.generate_interactive_roadmap(topic=\"Quantum Superposition\")", output: "")
    ]
    
    // --- STATIC DESIGN PALETTE ---
    private let textColors = ["#FFFFFF", "#EC4899", "#8B5CF6", "#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#9CA3AF"]
    private let highlights = ["#000000", "#3F0C2F", "#1D0D3F", "#0A2540", "#062E1C", "#3C2203", "#3C0B0B", "#27272A"]
    private let fontOptions = ["Arial", "Georgia", "Courier", "Times New Roman", "Inter", "JetBrains Mono"]
    private let styleOptions = ["Normal Text", "Heading 1", "Heading 2", "Heading 3"]
    private let zoomOptions = [50, 75, 100, 125, 150, 200]
    
    public init(isMobile: Bool = false) {
        self.isMobile = isMobile
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. TOP HEADER / TITLE DECK
            renderTopHeader()
                .border(width: 1, edges: [.bottom], color: Color.white.opacity(0.08))
            
            // 2. FILE MENUS BAR (Office Row)
            renderOfficeMenusRow()
                .border(width: 1, edges: [.bottom], color: Color.white.opacity(0.08))
            
            // 3. EDITING TOOLBAR
            if selectedMode == "Document" {
                renderFormattingToolbar()
                    .border(width: 1, edges: [.bottom], color: Color.white.opacity(0.08))
            }
            
            // 4. MAIN WORKSPACE WITH INTEGRATED SIDEBARS
            HStack(spacing: 0) {
                ZStack(alignment: .center) {
                    // Left Outline Sidebar (collapsible)
                    if isOutlineOpen {
                        HStack {
                            renderOutlineSidebar()
                            Spacer()
                        }
                        .transition(.move(edge: .leading))
                    }
                    
                    // Right AI Companion Sidebar (collapsible)
                    if isUnisonAiOpen {
                        HStack {
                            Spacer()
                            renderUnisonAiSidebar()
                        }
                        .transition(.move(edge: .trailing))
                    }
                    
                    // Document Canvas Area or Jupyter Deck
                    VStack(spacing: 0) {
                        if selectedMode == "Document" {
                            renderDocumentViewport()
                        } else if selectedMode == "Jupyter" {
                            renderJupyterViewport()
                        } else {
                            renderAiChatViewport()
                        }
                        
                        // Live Stats Footer Bar
                        renderStatusFooter()
                            .border(width: 1, edges: [.top], color: Color.white.opacity(0.08))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(unisonColor(from: "16171B"))
                    .cornerRadius(isOutlineOpen || isUnisonAiOpen ? 16 : 0)
                    .shadow(color: Color.black.opacity(isOutlineOpen || isUnisonAiOpen ? 0.45 : 0.0), radius: 10, x: isOutlineOpen ? -8 : (isUnisonAiOpen ? 8 : 0), y: 5)
                    .scaleEffect(isOutlineOpen || isUnisonAiOpen ? 0.94 : 1.0)
                    .offset(x: isOutlineOpen ? 190 : (isUnisonAiOpen ? -220 : 0))
                    .animation(.spring(response: 0.4, dampingFraction: 0.82, blendDuration: 0), value: isOutlineOpen)
                    .animation(.spring(response: 0.4, dampingFraction: 0.82, blendDuration: 0), value: isUnisonAiOpen)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Right Inspector Deck & Web Browser
                if !isMobile && splitMode != "Full Canvas" {
                    VStack(spacing: 12) {
                        renderInspectorPanel()
                            .frame(height: 190)
                        
                        renderBrowserPanel()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(12)
                    .frame(width: 320)
                    .background(Color.black.opacity(0.15))
                    .border(width: 1, edges: [.leading], color: Color.white.opacity(0.08))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(unisonColor(from: "16171B"))
        .foregroundColor(.white)
        .onAppear {
            seedInitialElementsIfNeeded()
        }
    }
    
    // --- SEED CONTENT ENGINE ---
    private func seedInitialElementsIfNeeded() {
        if db.canvasElements.isEmpty {
            let initial = [
                CanvasElement(
                    id: "el1",
                    text: "1. CORE MATHEMATICAL VERIFICATION",
                    size: "20",
                    color: "#8B5CF6",
                    weight: "bold",
                    type: "Heading 2",
                    font: "Inter"
                ),
                CanvasElement(
                    id: "el2",
                    text: "We analyze functional boundary conditions for asymptotic limits and coordinate variables. The layout behaves dynamically based on local compiler constraints.",
                    size: "13",
                    color: "#FFFFFF",
                    weight: "normal",
                    type: "Paragraph",
                    font: "Arial"
                ),
                CanvasElement(
                    id: "el3",
                    text: "MIT OpenCourseWare Reference Platform",
                    size: "13",
                    color: "#3B82F6",
                    weight: "bold",
                    type: "Hyperlink",
                    font: "JetBrains Mono",
                    url: "https://ocw.mit.edu"
                ),
                CanvasElement(
                    id: "el4",
                    text: "2. GEOMETRIC LAND CLASSIFICATION",
                    size: "20",
                    color: "#EC4899",
                    weight: "bold",
                    type: "Heading 2",
                    font: "Inter"
                ),
                CanvasElement(
                    id: "el5",
                    text: "The coordinate records must match spatial ward factors as cataloged under GMC records. Access secure certificates in the portal node below.",
                    size: "13",
                    color: "#FFFFFF",
                    weight: "normal",
                    type: "Paragraph",
                    font: "Arial"
                ),
                CanvasElement(
                    id: "el6",
                    text: "Guwahati Municipal Corporation NOC Portal",
                    size: "13",
                    color: "#10B981",
                    weight: "bold",
                    type: "Hyperlink",
                    font: "JetBrains Mono",
                    url: "https://gmc.assam"
                )
            ]
            db.saveCanvasElementsToServer(elements: initial)
            saveHistory(elements: initial)
        }
    }
    
    // --- 1. RENDERS: TOP HEADER PANEL ---
    private func renderTopHeader() -> some View {
        HStack(spacing: 12) {
            // App Document Branding
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.indigo)
                    .font(.system(size: 14))
                
                TextField("Document Name", text: $documentTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 80)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .onChange(of: documentTitle) { newValue in
                        triggerAutoSave()
                    }
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            
            // Star Button
            Button(action: {
                isStarred.toggle()
                triggerHaptic()
            }) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundColor(isStarred ? .yellow : .gray)
            }
            .buttonStyle(.plain)
            
            // Saved status indicator
            HStack(spacing: 4) {
                Image(systemName: "cloud.checkmark.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.emerald)
                Text(saveStatus)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            
            // Save Now Manual Action
            Button(action: {
                triggerManualSave()
            }) {
                Text("Save Now")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // CENTER: Document vs Jupyter Mode Switcher (Tab bar style)
            HStack(spacing: 2) {
                Button(action: {
                    selectedMode = "Document"
                    triggerHaptic()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.plaintext")
                        Text("Document")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(documentTabFg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(documentTabBg)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    selectedMode = "Jupyter"
                    triggerHaptic()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal.fill")
                        Text("Jupyter")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(jupyterTabFg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(jupyterTabBg)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    selectedMode = "AI Chat"
                    triggerHaptic()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                        Text("AI Chat")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(aiChatTabFg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(aiChatTabBg)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(2)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            
            Spacer()
            
            // RIGHT: Actions
            HStack(spacing: 10) {
                Button(action: {
                    showSettingsPopover.toggle()
                    triggerHaptic()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettingsPopover) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workspace Config")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.indigo)
                        
                        Toggle("Haptic Feedback", isOn: $db.hapticFeedbackEnabled)
                        Toggle("Sound FX", isOn: $db.soundFXEnabled)
                        Toggle("Continuous Control", isOn: Binding(
                            get: { AgentStateController.shared.bypassOperatorYield },
                            set: { AgentStateController.shared.bypassOperatorYield = $0 }
                        ))
                        
                        Divider()
                        
                        Button("Reset Custom Bounds") {
                            seedInitialElementsIfNeeded()
                            showSettingsPopover = false
                        }
                        .foregroundColor(.red)
                    }
                    .font(.system(size: 11))
                    .padding(14)
                    .frame(width: 200)
                    .background(unisonColor(from: "1A1B1F"))
                }
                
                // Blue Share Button (Matches Google Docs)
                Button(action: {
                    triggerHaptic()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                        Text("Share")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // User Profile
                Text("J")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.emerald)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(unisonColor(from: "121316"))
    }
    
    // --- 2. RENDERS: OFFICE MENUS ROW ---
    private func renderOfficeMenusRow() -> some View {
        HStack {
            HStack(spacing: 12) {
                renderMenuHeaderButton(name: "File")
                renderMenuHeaderButton(name: "Edit")
                renderMenuHeaderButton(name: "View")
                renderMenuHeaderButton(name: "Insert")
                renderMenuHeaderButton(name: "Format")
                renderMenuHeaderButton(name: "Tools")
                renderMenuHeaderButton(name: "Help")
            }
            
            Spacer()
            
            // Standard Split Selector
            if !isMobile {
                Menu {
                    Button(action: { splitMode = "Standard Split" }) {
                        Label("Standard Split", systemImage: "rectangle.split.2x1")
                    }
                    Button(action: { splitMode = "Full Canvas" }) {
                        Label("Full Canvas Only", systemImage: "square")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                        Text(splitMode)
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(unisonColor(from: "16171B"))
        .overlay(
            Group {
                if let active = activeMenu {
                    renderMenuDropdown(for: active)
                }
            }
        )
    }
    
    private func renderMenuHeaderButton(name: String) -> some View {
        Button(action: {
            if activeMenu == name {
                activeMenu = nil
            } else {
                activeMenu = name
            }
            triggerHaptic()
        }) {
            Text(name)
                .font(.system(size: 11))
                .foregroundColor(activeMenu == name ? .blue : .zinc300)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(activeMenu == name ? Color.white.opacity(0.08) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func renderMenuDropdown(for menu: String) -> some View {
        VStack {
            Spacer()
                .frame(height: 58)
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    if menu == "File" {
                        renderDropdownItem(label: "Insert New Item", icon: "plus") {
                            addNewDefaultElement()
                        }
                        renderDropdownItem(label: "Save Changes", icon: "arrow.up.doc") {
                            triggerManualSave()
                        }
                        renderDropdownItem(label: "Reset Default Canvas", icon: "arrow.counterclockwise") {
                            db.saveCanvasElementsToServer(elements: [])
                            seedInitialElementsIfNeeded()
                        }
                    } else if menu == "Edit" {
                        renderDropdownItem(label: "Undo last edit", icon: "arrow.uturn.backward") {
                            triggerUndo()
                        }
                        renderDropdownItem(label: "Redo action", icon: "arrow.uturn.forward") {
                            triggerRedo()
                        }
                        renderDropdownItem(label: "Delete Selected", icon: "trash") {
                            deleteSelectedElement()
                        }
                        renderDropdownItem(label: "Clear All", icon: "clear") {
                            db.saveCanvasElementsToServer(elements: [])
                        }
                    } else if menu == "View" {
                        renderDropdownItem(label: "Zoom In (+25%)", icon: "plus.magnifyingglass") {
                            zoomPercent = min(200, zoomPercent + 25)
                        }
                        renderDropdownItem(label: "Zoom Out (-25%)", icon: "minus.magnifyingglass") {
                            zoomPercent = max(50, zoomPercent - 25)
                        }
                        renderDropdownItem(label: "Actual Size (100%)", icon: "magnifyingglass") {
                            zoomPercent = 100
                        }
                    } else if menu == "Insert" {
                        renderDropdownItem(label: "Insert Heading 1", icon: "text.alignleft") {
                            insertElement(type: "Heading 1", text: "New Heading 1")
                        }
                        renderDropdownItem(label: "Insert Heading 2", icon: "text.alignleft") {
                            insertElement(type: "Heading 2", text: "New Heading 2")
                        }
                        renderDropdownItem(label: "Insert Body Text", icon: "doc.text") {
                            insertElement(type: "Paragraph", text: "New body paragraph content.")
                        }
                        renderDropdownItem(label: "Insert Hyperlink", icon: "link") {
                            insertElement(type: "Hyperlink", text: "New Hyperlink", url: "https://wikipedia.org")
                        }
                    } else if menu == "Format" {
                        renderDropdownItem(label: "Bold text", icon: "bold") {
                            toggleBoldOnSelected()
                        }
                        renderDropdownItem(label: "Italic text", icon: "italic") {
                            toggleItalicOnSelected()
                        }
                        renderDropdownItem(label: "Underline text", icon: "underline") {
                            toggleUnderlineOnSelected()
                        }
                    } else {
                        renderDropdownItem(label: "Support Desk", icon: "questionmark.circle") {}
                        renderDropdownItem(label: "About Unison OS", icon: "info.circle") {}
                    }
                }
                .padding(8)
                .background(unisonColor(from: "1C1D22"))
                .cornerRadius(8)
                .shadow(radius: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .frame(width: 190)
                .offset(x: getMenuOffset(for: menu))
                
                Spacer()
            }
            Spacer()
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    activeMenu = nil
                }
        )
    }
    
    private func getMenuOffset(for menu: String) -> CGFloat {
        switch menu {
        case "File": return 16
        case "Edit": return 55
        case "View": return 95
        case "Insert": return 135
        case "Format": return 185
        case "Tools": return 240
        default: return 280
        }
    }
    
    private func renderDropdownItem(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            activeMenu = nil
            triggerHaptic()
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // --- 3. RENDERS: FORMATTING TOOLBAR ---
    private func renderFormattingToolbar() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Undo / Redo
                Button(action: { triggerUndo() }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Button(action: { triggerRedo() }) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Group {
                    Divider()
                        .frame(height: 16)
                        .background(Color.white.opacity(0.12))
                    
                    // Print & Pin
                    Button(action: {}) {
                        Image(systemName: "printer")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {}) {
                        Image(systemName: "pin")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {}) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .frame(height: 16)
                        .background(Color.white.opacity(0.12))
                }
                
                // Zoom Selection Dropdown
                HStack(spacing: 4) {
                    Text("\(zoomPercent)%")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04))
                .cornerRadius(4)
                .onTapGesture {
                    showZoomDropdown.toggle()
                }
                .popover(isPresented: $showZoomDropdown) {
                    VStack(spacing: 4) {
                        ForEach(zoomOptions, id: \.self) { val in
                            Button("\(val)%") {
                                zoomPercent = val
                                showZoomDropdown = false
                                triggerHaptic()
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                    }
                    .font(.system(size: 10))
                    .padding(8)
                    .background(unisonColor(from: "1A1B1F"))
                }
                
                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.12))
                
                // Text Style Dropdown
                HStack(spacing: 4) {
                    Text(selectedStyle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04))
                .cornerRadius(4)
                .onTapGesture {
                    showStyleDropdown.toggle()
                }
                .popover(isPresented: $showStyleDropdown) {
                    VStack(spacing: 4) {
                        ForEach(styleOptions, id: \.self) { style in
                            Button(style) {
                                selectedStyle = style
                                formatSelectedElementStyle(style)
                                showStyleDropdown = false
                                triggerHaptic()
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                    }
                    .font(.system(size: 10))
                    .padding(8)
                    .background(unisonColor(from: "1A1B1F"))
                }
                
                // Font Family Dropdown
                HStack(spacing: 4) {
                    Text(selectedFont)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04))
                .cornerRadius(4)
                .onTapGesture {
                    showFontDropdown.toggle()
                }
                .popover(isPresented: $showFontDropdown) {
                    VStack(spacing: 4) {
                        ForEach(fontOptions, id: \.self) { font in
                            Button(font) {
                                selectedFont = font
                                formatSelectedElementFont(font)
                                showFontDropdown = false
                                triggerHaptic()
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                    }
                    .font(.system(size: 10))
                    .padding(8)
                    .background(unisonColor(from: "1A1B1F"))
                }
                
                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.12))
                
                // Size controls: - Display +
                HStack(spacing: 6) {
                    Button(action: {
                        selectedSize = max(8, selectedSize - 1)
                        formatSelectedElementSize(selectedSize)
                    }) {
                        Image(systemName: "minus")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(selectedSize)")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 16, alignment: .center)
                    
                    Button(action: {
                        selectedSize = min(72, selectedSize + 1)
                        formatSelectedElementSize(selectedSize)
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04))
                .cornerRadius(4)
                
                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.12))
                
                // Formatting Toggles: B, I, U
                HStack(spacing: 4) {
                    Button(action: {
                        isBold.toggle()
                        toggleBoldOnSelected()
                    }) {
                        Text("B")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isBold ? .blue : .white)
                            .frame(width: 18, height: 18)
                            .background(isBold ? Color.white.opacity(0.12) : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        isItalic.toggle()
                        toggleItalicOnSelected()
                    }) {
                        Text("I")
                            .font(.system(size: 11, weight: .medium)).italic()
                            .foregroundColor(isItalic ? .blue : .white)
                            .frame(width: 18, height: 18)
                            .background(isItalic ? Color.white.opacity(0.12) : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        isUnderline.toggle()
                        toggleUnderlineOnSelected()
                    }) {
                        Text("U")
                            .font(.system(size: 11, weight: .medium)).underline()
                            .foregroundColor(isUnderline ? .blue : .white)
                            .frame(width: 18, height: 18)
                            .background(isUnderline ? Color.white.opacity(0.12) : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
                
                // Color swatches picker
                Button(action: { showColorDropdown.toggle() }) {
                    HStack(spacing: 2) {
                        Text("A")
                            .font(.system(size: 11, weight: .bold))
                            .underline()
                        Circle()
                            .fill(unisonColor(from: selectedColorHex))
                            .frame(width: 8, height: 8)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showColorDropdown) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Text Colors")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.gray)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 6), count: 4)) {
                            ForEach(textColors, id: \.self) { colorHex in
                                Button(action: {
                                    selectedColorHex = colorHex
                                    formatSelectedElementColor(colorHex)
                                    showColorDropdown = false
                                    triggerHaptic()
                                }) {
                                    Circle()
                                        .fill(unisonColor(from: colorHex))
                                        .frame(width: 16, height: 16)
                                        .overlay(
                                            Circle().stroke(Color.white.opacity(0.3), lineWidth: selectedColorHex == colorHex ? 1.5 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(8)
                    .background(unisonColor(from: "1A1B1F"))
                }
                
                // Highlight swatches picker
                Button(action: { showHighlightDropdown.toggle() }) {
                    HStack(spacing: 2) {
                        Image(systemName: "pencil.tip")
                            .font(.system(size: 10))
                        Circle()
                            .fill(unisonColor(from: selectedHighlightHex))
                            .frame(width: 8, height: 8)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showHighlightDropdown) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Highlights")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.gray)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 6), count: 4)) {
                            ForEach(highlights, id: \.self) { hexVal in
                                Button(action: {
                                    selectedHighlightHex = hexVal
                                    showHighlightDropdown = false
                                    triggerHaptic()
                                }) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(unisonColor(from: hexVal))
                                        .frame(width: 16, height: 16)
                                        .border(Color.white.opacity(0.2), width: 1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(8)
                    .background(unisonColor(from: "1A1B1F"))
                }
                
                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.12))
                
                // Alignments
                HStack(spacing: 4) {
                    renderAlignmentBtn(type: "Left", icon: "text.alignleft")
                    renderAlignmentBtn(type: "Center", icon: "text.aligncenter")
                    renderAlignmentBtn(type: "Right", icon: "text.alignright")
                }
                
                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.12))
                
                // Add / Delete Elements
                HStack(spacing: 6) {
                    Button(action: { addNewDefaultElement() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { deleteSelectedElement() }) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
        }
        .background(unisonColor(from: "141518"))
    }
    
    private func renderAlignmentBtn(type: String, icon: String) -> some View {
        Button(action: {
            textAlignment = type
            triggerHaptic()
        }) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(textAlignment == type ? .blue : .white)
                .frame(width: 18, height: 18)
                .background(textAlignment == type ? Color.white.opacity(0.12) : Color.clear)
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
    
    // --- 4. OUTLINE SIDEBAR PANEL ---
    private func renderOutlineSidebar() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DOCUMENT OUTLINE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.indigo)
                Spacer()
                Button(action: { isOutlineOpen = false }) {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(db.canvasElements.filter { $0.type.starts(with: "Heading") }) { heading in
                        Button(action: {
                            selectedCanvasElementId = heading.id
                            triggerHaptic()
                        }) {
                            HStack {
                                Circle()
                                    .fill(Color.indigo)
                                    .frame(width: 4, height: 4)
                                Text(heading.text)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(selectedCanvasElementId == heading.id ? .indigo : .white)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if db.canvasElements.filter({ $0.type.starts(with: "Heading") }).isEmpty {
                        Text("No headings found on canvas outline.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 190)
        .background(unisonColor(from: "141518"))
        .border(width: 1, edges: [.trailing], color: Color.white.opacity(0.08))
    }
    
    // --- 5. UNISON AI COMPANION SIDEBAR ---
    private func renderUnisonAiSidebar() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("UNISON AI")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.purple)
                Spacer()
                Button(action: { isUnisonAiOpen = false }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.gray)
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)
            
            Text("Power up your syllabus planning and code checks through Central AI.")
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .lineLimit(2)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if aiMessages.isEmpty {
                            VStack(alignment: .center, spacing: 8) {
                                Image(systemName: "brain.headprofile")
                                    .font(.system(size: 20))
                                    .foregroundColor(.gray.opacity(0.4))
                                Text("Ready to generate layout outlines, math derivations, or coordinate check blocks.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(aiMessages) { msg in
                                renderMessageRow(msg: msg)
                                    .id(msg.id)
                            }
                        }
                    }
                }
                .onChange(of: aiMessages.count) { _ in
                    if let last = aiMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Text Entry
            HStack(spacing: 6) {
                TextField("Ask AI...", text: $aiInputMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(6)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                Button(action: {
                    runAiSimulation()
                }) {
                    if isAiThinking {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                            .frame(width: 24, height: 24)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(unisonColor(from: "121316"))
        .border(width: 1, edges: [.leading], color: Color.white.opacity(0.08))
    }
    
    private func renderMessageRow(msg: ChatMessage) -> some View {
        let isUser = msg.role == "user"
        let roleText = isUser ? "YOU" : "UNISON AI"
        let roleColor = isUser ? Color.blue : Color.purple
        let bgOpacityColor = isUser ? Color.blue.opacity(0.08) : Color.purple.opacity(0.08)
        let strokeColor = isUser ? Color.blue.opacity(0.2) : Color.purple.opacity(0.2)
        
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(roleText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(roleColor)
                Spacer()
            }
            
            FormattedResponseView(text: msg.content)
                .padding(8)
                .background(bgOpacityColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(strokeColor, lineWidth: 1)
                )
            
            if msg.role == "model" {
                Button(action: {
                    insertElement(type: "Paragraph", text: msg.content)
                    triggerHaptic()
                }) {
                    HStack {
                        Image(systemName: "plus.square.on.square")
                        Text("Insert onto Canvas")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.purple)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func runAiSimulation() {
        guard !aiInputMessage.isEmpty else { return }
        let prompt = aiInputMessage
        aiInputMessage = ""
        
        let userMsg = ChatMessage(role: "user", content: prompt)
        aiMessages.append(userMsg)
        isAiThinking = true
        
        db.generateGeminiResponseDirect(prompt: prompt, history: aiMessages.dropLast()) { responseText in
            DispatchQueue.main.async {
                self.isAiThinking = false
                if let reply = responseText {
                    let modelMsg = ChatMessage(role: "model", content: reply)
                    self.aiMessages.append(modelMsg)
                } else {
                    let errorMsg = ChatMessage(role: "model", content: "Error: Failed to get response from Unison AI. Verify network connection.")
                    self.aiMessages.append(errorMsg)
                }
                triggerHaptic()
            }
        }
    }
    
    // --- 6. DOCUMENT VIEWPORT & centered PageSheet ---
    private func renderDocumentViewport() -> some View {
        ScrollView {
            VStack {
                HStack {
                    // Float sidebar toggle inside the Canvas area (like screenshot)
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            isOutlineOpen.toggle()
                            if isOutlineOpen {
                                isUnisonAiOpen = false
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sidebar.left")
                            Text("Outline")
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            isUnisonAiOpen.toggle()
                            if isUnisonAiOpen {
                                isOutlineOpen = false
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("UNISON AI")
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                
                // Centered Floating Page Sheet (Matches the beautiful screenshot)
                VStack(spacing: 0) {
                    // Document Header line: PAGE / Jupyter state indicator
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                            Text("PAGE 1 OF 1")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                        
                        Spacer()
                        
                        Text("In [1]:")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Center TEST syllabus card (looks exactly like the screenshot!)
                    VStack(spacing: 12) {
                        Text("COURSE VOLUME I")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.blue)
                            .tracking(4)
                        
                        Text(documentTitle.uppercased())
                            .font(.system(size: 32, weight: .black))
                            .foregroundColor(.white)
                            .tracking(2)
                            .multilineTextAlignment(.center)
                        
                        Text("An exquisite interactive coursebook, syllabus outline, and progressive daily workspace.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.zinc300)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .frame(maxWidth: 480)
                        
                        // Gradient line divider
                        RoundedRectangle(cornerRadius: 99)
                            .fill(LinearGradient(colors: [.indigo, .pink], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 80, height: 3)
                            .padding(.vertical, 8)
                        
                        Text("CREATED BY SCHOLAR")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                            .tracking(3)
                        
                        Text("BHABA JYOTI DAS")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 40)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.01))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.03), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.vertical, 16)
                        .padding(.horizontal, 16)
                    
                    // Editable canvas list elements
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(db.canvasElements) { element in
                            VStack(alignment: .leading, spacing: 6) {
                                let isSelected = selectedCanvasElementId == element.id
                                
                                HStack(alignment: .top, spacing: 8) {
                                    // Bullet if Normal block
                                    if element.type == "Paragraph" {
                                        Circle()
                                            .fill(Color.white.opacity(0.3))
                                            .frame(width: 5, height: 5)
                                            .offset(y: 6)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        if isSelected {
                                            // Editable dynamic text input field! Extremely usable!
                                            TextEditor(text: Binding(
                                                get: { element.text },
                                                set: { newText in
                                                    updateElementText(element.id, to: newText)
                                                }
                                            ))
                                            .font(getElementFont(for: element))
                                            .foregroundColor(isSelected ? .blue : getElementColor(for: element))
                                            .frame(minHeight: 40)
                                            .padding(4)
                                            .background(Color.black.opacity(0.3))
                                            .cornerRadius(4)
                                        } else {
                                            // Display mode
                                            Text(element.text)
                                                .font(getElementFont(for: element))
                                                .foregroundColor(getElementColor(for: element))
                                                .underline(element.type == "Hyperlink")
                                        }
                                        
                                        // Metadata overlay on Selection
                                        if isSelected {
                                            HStack(spacing: 8) {
                                                Text("Font: \(element.font)")
                                                Text("Size: \(element.size)px")
                                                if let url = element.url {
                                                    Text("URL: \(url)")
                                                        .foregroundColor(.blue)
                                                }
                                                Spacer()
                                                
                                                // Ordering Actions
                                                Button(action: { moveElementUp(element.id) }) {
                                                    Image(systemName: "arrow.up")
                                                        .font(.system(size: 9))
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button(action: { moveElementDown(element.id) }) {
                                                    Image(systemName: "arrow.down")
                                                        .font(.system(size: 9))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(.gray)
                                            .padding(.top, 2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(8)
                                .background(isSelected ? Color.indigo.opacity(0.08) : Color.clear)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? Color.indigo.opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                                .onTapGesture {
                                    selectedCanvasElementId = element.id
                                    selectedFont = element.font
                                    selectedStyle = element.type
                                    if let sizeInt = Int(element.size) {
                                        selectedSize = sizeInt
                                    }
                                    selectedColorHex = element.color
                                    if let url = element.url {
                                        canvasBrowserUrl = url
                                    }
                                    triggerHaptic()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: 816)
                .background(unisonColor(from: "1E1E1E"))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.6), radius: 20, x: 0, y: 10)
                .scaleEffect(CGFloat(zoomPercent) / 100.0)
                .animation(.spring(), value: zoomPercent)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(unisonColor(from: "16171B"))
    }
    
    // --- 7. JUPYTER DECK VIEWPORT ---
    private func renderJupyterViewport() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.orange)
                    Text("JUPYTER INTERACTIVE NOTEBOOK")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                    Spacer()
                    
                    Button(action: {
                        // Reset all cells
                        for idx in jupyterCells.indices {
                            jupyterCells[idx].output = ""
                            jupyterCells[idx].hasRun = false
                        }
                    }) {
                        Label("Clear Outputs", systemImage: "clear")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)
                
                ForEach(jupyterCells.indices, id: \.self) { idx in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("In [\(idx + 1)]:")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                            Spacer()
                            
                            Button(action: {
                                runJupyterCell(at: idx)
                            }) {
                                HStack {
                                    if jupyterCells[idx].isRunning {
                                        ProgressView()
                                            .scaleEffect(0.5)
                                    } else {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(.green)
                                    }
                                    Text("Run Cell")
                                }
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Code editor block
                        TextEditor(text: $jupyterCells[idx].code)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(8)
                            .frame(height: 60)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        
                        // Executed output block
                        if jupyterCells[idx].hasRun {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Output [\(idx + 1)]:")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                                
                                Text(jupyterCells[idx].output)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(white: 0.05))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(8)
                    .border(width: 1, edges: [.leading], color: Color.orange.opacity(0.3))
                }
            }
            .padding(24)
        }
        .background(unisonColor(from: "16171B"))
    }
    
    private func runJupyterCell(at index: Int) {
        jupyterCells[index].isRunning = true
        triggerHaptic()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            jupyterCells[index].isRunning = false
            jupyterCells[index].hasRun = true
            
            let code = jupyterCells[index].code
            if code.contains("verify") {
                jupyterCells[index].output = "● BOUNDARY PARAMETERS: VERIFIED SUCCESS\nAsymptotic verification satisfied.\nNodes generated: 6 | Edges active: 4"
            } else if code.contains("boundary") {
                jupyterCells[index].output = "● GEOGRAPHIC RESOLUTION:\nGuwahati ward valuation matches spatial factor of 1.42.\nStatus: CLEARANCE APPROVED."
            } else if code.contains("roadmap") {
                jupyterCells[index].output = "● ROADMAP RENDERED:\n- Chapter 1: Complexity bounds\n- Chapter 2: Real-world clearances\nData synchronized successfully with centralized database server."
            } else {
                jupyterCells[index].output = "Operation executed successfully.\nProcess exited with status 0."
            }
            triggerHaptic()
        }
    }
    
    // --- 8. STATUS FOOTER BAR ---
    private func renderStatusFooter() -> some View {
        HStack {
            HStack(spacing: 12) {
                Text("Page 1 of 1")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
                
                Text("Words: \(calculateWords())")
                Text("Characters: \(calculateCharacters())")
            }
            .font(.system(size: 10))
            .foregroundColor(.gray)
            
            Spacer()
            
            HStack(spacing: 8) {
                Text("Google Docs Mode")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.blue)
                
                Circle()
                    .fill(Color.emerald)
                    .frame(width: 6, height: 6)
                Text("Cloud Synced")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.emerald)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(unisonColor(from: "121316"))
    }
    
    // --- 9. INSPECTOR PANEL (Right side) ---
    private func renderInspectorPanel() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundColor(.amber)
                Text("Document State Inspector")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.amber)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.02))
            
            if let selectedId = selectedCanvasElementId, let element = db.canvasElements.first(where: { $0.id == selectedId }) {
                VStack(alignment: .leading, spacing: 8) {
                    inspectorRow(label: "Element Type:", value: element.type, isMonospaced: true)
                    inspectorRow(label: "Font Family:", value: element.font, isMonospaced: true)
                    inspectorRow(label: "Font Size:", value: element.size + "px", isMonospaced: true)
                    
                    HStack {
                        Text("Text Color:")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(unisonColor(from: element.color))
                                .frame(width: 8, height: 8)
                            Text(element.color)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Direct Edit Field
                    HStack {
                        Text("Edit Text:")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Spacer()
                        TextField("Text", text: Binding(
                            get: { element.text },
                            set: { val in updateElementText(element.id, to: val) }
                        ))
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .textFieldStyle(.plain)
                        .padding(3)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(3)
                        .frame(width: 140)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            } else {
                Text("Click any element in the document canvas sheet to inspect properties (size, color, weight, type).")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .padding(14)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    private func inspectorRow(label: String, value: String, isMonospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: isMonospaced ? .monospaced : .default))
                .foregroundColor(.white)
        }
    }
    
    // --- 10. BROWSER PANEL (Right side) ---
    private func renderBrowserPanel() -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "safari")
                    .font(.system(size: 11))
                    .foregroundColor(.cyan)
                Text("Integrated Web Browser")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                Spacer()
                Circle()
                    .fill(isBrowserLoading ? Color.yellow : Color.green)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.02))
            
            // Fake address bar
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.green)
                    Text(canvasBrowserUrl)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4))
                .cornerRadius(4)
                
                Button(action: {
                    isBrowserLoading = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        isBrowserLoading = false
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(Color.white.opacity(0.01))
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // Web view simulation contents
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if canvasBrowserUrl.contains("wikipedia") {
                        Text("Wikipedia: Quantum Superposition")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("Quantum superposition is a fundamental principle of quantum mechanics. It states that, much like waves in classical physics, any two (or more) quantum states can be added together and the result will be another valid quantum state.")
                            .font(.system(size: 11))
                            .foregroundColor(.zinc300)
                            .lineSpacing(3)
                    } else if canvasBrowserUrl.contains("ocw.mit.edu") {
                        Text("MIT OpenCourseWare: Complexity Proofs")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("In analyzing recursive divide-and-conquer algorithms, we solve recurrences of the form T(n) = aT(n/b) + f(n) under asymptotic boundaries.")
                            .font(.system(size: 11))
                            .foregroundColor(.zinc300)
                            .lineSpacing(3)
                    } else if canvasBrowserUrl.contains("gmc.assam") {
                        Text("Guwahati Municipal Corporation NOC Portal")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("Official land valuation factors and property clearance systems. Ward 14 spatial coordinates are synchronized cleanly.")
                            .font(.system(size: 11))
                            .foregroundColor(.zinc300)
                            .lineSpacing(3)
                    } else {
                        Text("Integrated Browser Homepage")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("Click a link within the canvas sheet document to load simulated scientific reference tunnels.")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                .padding(14)
            }
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    // --- CANVAS MANIPULATION ENGINE ---
    private func updateElementText(_ id: String, to newText: String) {
        let updated = db.canvasElements.map { el in
            if el.id == id {
                return CanvasElement(
                    id: el.id,
                    text: newText,
                    size: el.size,
                    color: el.color,
                    weight: el.weight,
                    type: el.type,
                    font: el.font,
                    url: el.url
                )
            }
            return el
        }
        db.saveCanvasElementsToServer(elements: updated)
        saveHistory(elements: updated)
        triggerAutoSave()
    }
    
    private func formatSelectedElementStyle(_ styleName: String) {
        guard let selectedId = selectedCanvasElementId else { return }
        let sizeMap = ["Normal Text": "14", "Heading 1": "28", "Heading 2": "20", "Heading 3": "16"]
        let weightMap = ["Normal Text": "normal", "Heading 1": "bold", "Heading 2": "bold", "Heading 3": "bold"]
        
        let targetSize = sizeMap[styleName] ?? "14"
        let targetWeight = weightMap[styleName] ?? "normal"
        
        let updated = db.canvasElements.map { el in
            if el.id == selectedId {
                return CanvasElement(
                    id: el.id,
                    text: el.text,
                    size: targetSize,
                    color: el.color,
                    weight: targetWeight,
                    type: styleName,
                    font: el.font,
                    url: el.url
                )
            }
            return el
        }
        db.saveCanvasElementsToServer(elements: updated)
        saveHistory(elements: updated)
    }
    
    private func formatSelectedElementFont(_ fontName: String) {
        guard let selectedId = selectedCanvasElementId else { return }
        let updated = db.canvasElements.map { el in
            if el.id == selectedId {
                return CanvasElement(
                    id: el.id,
                    text: el.text,
                    size: el.size,
                    color: el.color,
                    weight: el.weight,
                    type: el.type,
                    font: fontName,
                    url: el.url
                )
            }
            return el
        }
        db.saveCanvasElementsToServer(elements: updated)
        saveHistory(elements: updated)
    }
    
    private func formatSelectedElementSize(_ sizeInt: Int) {
        guard let selectedId = selectedCanvasElementId else { return }
        let updated = db.canvasElements.map { el in
            if el.id == selectedId {
                return CanvasElement(
                    id: el.id,
                    text: el.text,
                    size: String(sizeInt),
                    color: el.color,
                    weight: el.weight,
                    type: el.type,
                    font: el.font,
                    url: el.url
                )
            }
            return el
        }
        db.saveCanvasElementsToServer(elements: updated)
        saveHistory(elements: updated)
    }
    
    private func formatSelectedElementColor(_ colorHex: String) {
        guard let selectedId = selectedCanvasElementId else { return }
        let updated = db.canvasElements.map { el in
            if el.id == selectedId {
                return CanvasElement(
                    id: el.id,
                    text: el.text,
                    size: el.size,
                    color: colorHex,
                    weight: el.weight,
                    type: el.type,
                    font: el.font,
                    url: el.url
                )
            }
            return el
        }
        db.saveCanvasElementsToServer(elements: updated)
        saveHistory(elements: updated)
    }
    
    private func toggleBoldOnSelected() {
        guard let selectedId = selectedCanvasElementId else { return }
        let updated = db.canvasElements.map { el in
            if el.id == selectedId {
                let currentIsBold = el.weight.lowercased() == "bold"
                return CanvasElement(
                    id: el.id,
                    text: el.text,
                    size: el.size,
                    color: el.color,
                    weight: currentIsBold ? "normal" : "bold",
                    type: el.type,
                    font: el.font,
                    url: el.url
                )
            }
            return el
        }
        db.saveCanvasElementsToServer(elements: updated)
        saveHistory(elements: updated)
    }
    
    private func toggleItalicOnSelected() {
        // Mock style alteration
        triggerHaptic()
    }
    
    private func toggleUnderlineOnSelected() {
        // Mock style alteration
        triggerHaptic()
    }
    
    private func addNewDefaultElement() {
        let newId = "el_custom_\(Date().timeIntervalSince1970)"
        let newElement = CanvasElement(
            id: newId,
            text: "New draft element outline content.",
            size: "14",
            color: "#FFFFFF",
            weight: "normal",
            type: "Paragraph",
            font: "Arial"
        )
        let nextList = db.canvasElements + [newElement]
        db.saveCanvasElementsToServer(elements: nextList)
        saveHistory(elements: nextList)
        selectedCanvasElementId = newId
        triggerHaptic()
    }
    
    private func deleteSelectedElement() {
        guard let selectedId = selectedCanvasElementId else { return }
        let filtered = db.canvasElements.filter { $0.id != selectedId }
        db.saveCanvasElementsToServer(elements: filtered)
        saveHistory(elements: filtered)
        selectedCanvasElementId = nil
        triggerHaptic()
    }
    
    private func insertElement(type: String, text: String, url: String? = nil) {
        let newId = "el_custom_\(Date().timeIntervalSince1970)"
        let sizeVal = type == "Heading 1" ? "28" : type == "Heading 2" ? "20" : "14"
        let weightVal = type.starts(with: "Heading") ? "bold" : "normal"
        let fontVal = type == "Hyperlink" ? "JetBrains Mono" : "Arial"
        let colorVal = type == "Hyperlink" ? "#3B82F6" : "#FFFFFF"
        
        let newElement = CanvasElement(
            id: newId,
            text: text,
            size: sizeVal,
            color: colorVal,
            weight: weightVal,
            type: type,
            font: fontVal,
            url: url
        )
        let nextList = db.canvasElements + [newElement]
        db.saveCanvasElementsToServer(elements: nextList)
        saveHistory(elements: nextList)
        selectedCanvasElementId = newId
    }
    
    private func moveElementUp(_ id: String) {
        var elements = db.canvasElements
        guard let index = elements.firstIndex(where: { $0.id == id }), index > 0 else { return }
        elements.swapAt(index, index - 1)
        db.saveCanvasElementsToServer(elements: elements)
        saveHistory(elements: elements)
    }
    
    private func moveElementDown(_ id: String) {
        var elements = db.canvasElements
        guard let index = elements.firstIndex(where: { $0.id == id }), index < elements.count - 1 else { return }
        elements.swapAt(index, index + 1)
        db.saveCanvasElementsToServer(elements: elements)
        saveHistory(elements: elements)
    }
    
    // --- HELPER HISTORY ROLLBACK ENGINE ---
    private func saveHistory(elements: [CanvasElement]) {
        canvasHistory.append(elements)
        if canvasHistory.count > 50 {
            canvasHistory.removeFirst()
        }
        redoHistory.removeAll()
    }
    
    private func triggerUndo() {
        guard canvasHistory.count > 1 else { return }
        let current = canvasHistory.removeLast()
        redoHistory.append(current)
        if let previous = canvasHistory.last {
            db.saveCanvasElementsToServer(elements: previous)
        }
        triggerHaptic()
    }
    
    private func triggerRedo() {
        guard let next = redoHistory.popLast() else { return }
        canvasHistory.append(next)
        db.saveCanvasElementsToServer(elements: next)
        triggerHaptic()
    }
    
    // --- METRICS GENERATOR ---
    private func calculateWords() -> Int {
        let totalText = db.canvasElements.map { $0.text }.joined(separator: " ")
        return totalText.split(separator: " ").count
    }
    
    private func calculateCharacters() -> Int {
        let totalText = db.canvasElements.map { $0.text }.joined(separator: "")
        return totalText.count
    }
    
    // --- AUTO-SAVE CHIME ENGINE ---
    private func triggerAutoSave() {
        saveStatus = "Saving..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            saveStatus = "Saved"
        }
    }
    
    private func triggerManualSave() {
        triggerAutoSave()
        db.saveCanvasElementsToServer(elements: db.canvasElements)
        triggerHaptic()
    }
    
    // --- DESIGN HELPER WRAPPERS ---
    private func getElementFont(for el: CanvasElement) -> Font {
        let size = CGFloat(Double(el.size) ?? 14.0)
        let isBoldVal = el.weight.lowercased() == "bold"
        
        if el.font.lowercased().contains("mono") {
            return .system(size: size, weight: isBoldVal ? .bold : .regular, design: .monospaced)
        } else if el.font.lowercased().contains("georgia") || el.font.lowercased().contains("times") {
            return .system(size: size, weight: isBoldVal ? .bold : .regular, design: .serif)
        } else {
            return .system(size: size, weight: isBoldVal ? .bold : .regular, design: .default)
        }
    }
    
    private func getElementColor(for el: CanvasElement) -> Color {
        return unisonColor(from: el.color)
    }
    
    private func triggerHaptic() {
        if db.hapticFeedbackEnabled {
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            #endif
        }
    }
    
    // MARK: - AI CODE CHAT & IDE MODE
    
    private func renderAiChatViewport() -> some View {
        HStack(spacing: 0) {
            // Left Pane: Code AI Chat
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.purple)
                    Text("CODE ASSISTANT")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.purple)
                    Spacer()
                }
                .padding(.bottom, 4)
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(codeChatMessages) { msg in
                                renderMessageRow(msg: msg)
                                    .id(msg.id)
                            }
                        }
                    }
                    .onChange(of: codeChatMessages.count) { _ in
                        if let last = codeChatMessages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    TextField("Request code changes or scripts...", text: $codeChatInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(6)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    
                    Button(action: {
                        sendCodeChatRequest()
                    }) {
                        if isCodeChatThinking {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.purple)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCodeChatThinking)
                }
            }
            .padding(14)
            .frame(width: 320)
            .background(unisonColor(from: "121316"))
            .border(width: 1, edges: [.trailing], color: Color.white.opacity(0.08))
            
            // Right Pane: Active File Code Editor
            VStack(spacing: 0) {
                // Tab Header bar
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.orange)
                        Text(activeCodeFile)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.05))
                    .border(width: 1, edges: [.trailing], color: Color.white.opacity(0.08))
                    
                    Spacer()
                    
                    // Action Buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            runActiveCode()
                        }) {
                            HStack(spacing: 4) {
                                if isCodeRunning {
                                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                                    Text("Running...")
                                } else {
                                    Image(systemName: "play.fill")
                                    Text("Run Code")
                                }
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isCodeRunning ? Color.gray : Color.green)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isCodeRunning)
                        
                        Button(action: {
                            copyToClipboard(text: activeCodeContent)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 16)
                }
                .frame(height: 36)
                .background(Color.black.opacity(0.2))
                .border(width: 1, edges: [.bottom], color: Color.white.opacity(0.08))
                
                // Code Content with Line Numbers
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 4) {
                        let linesCount = activeCodeContent.components(separatedBy: .newlines).count
                        ForEach(1...max(linesCount, 1), id: \.self) { lineNum in
                            Text("\(lineNum)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .frame(width: 32)
                    .background(Color.black.opacity(0.1))
                    .border(width: 1, edges: [.trailing], color: Color.white.opacity(0.05))
                    
                    // Code editor TextEditor
                    TextEditor(text: $activeCodeContent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.2))
                }
                
                // Console / Run output
                if !codeExecutionOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("CONSOLE OUTPUT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                            Button(action: { codeExecutionOutput = "" }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.3))
                        
                        ScrollView {
                            Text(codeExecutionOutput)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(height: 120)
                        .background(Color.black.opacity(0.5))
                    }
                    .border(width: 1, edges: [.top], color: Color.white.opacity(0.08))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(unisonColor(from: "1a1b1f"))
        }
    }
    
    private func copyToClipboard(text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
    
    private func runActiveCode() {
        guard !isCodeRunning else { return }
        isCodeRunning = true
        codeExecutionOutput = "Running script...\n"
        
        let fileExtension = activeCodeFile.components(separatedBy: ".").last ?? "py"
        let tempDir = NSTemporaryDirectory()
        let tempFilePath = (tempDir as NSString).appendingPathComponent(activeCodeFile)
        
        do {
            try activeCodeContent.write(toFile: tempFilePath, atomically: true, encoding: .utf8)
            
            let cmd: String
            if fileExtension == "py" {
                cmd = "python3 \"\(tempFilePath)\""
            } else if fileExtension == "js" {
                cmd = "node \"\(tempFilePath)\""
            } else if fileExtension == "sh" {
                cmd = "bash \"\(tempFilePath)\""
            } else {
                cmd = "cat \"\(tempFilePath)\""
            }
            
            LocalShellExecutor.shared.execute(command: cmd, in: tempDir) { status, output in
                DispatchQueue.main.async {
                    self.isCodeRunning = false
                    self.codeExecutionOutput = output
                }
            }
        } catch {
            self.isCodeRunning = false
            self.codeExecutionOutput = "Failed to write file locally: \(error.localizedDescription)"
        }
    }
    
    private func sendCodeChatRequest() {
        guard !codeChatInput.isEmpty else { return }
        let prompt = codeChatInput
        codeChatInput = ""
        
        let userMsg = ChatMessage(role: "user", content: prompt)
        codeChatMessages.append(userMsg)
        isCodeChatThinking = true
        
        let systemContext = "You are AI Code Studio inside Unison OS. Write clean code. The user is currently working on a file named '\(activeCodeFile)' with the following contents:\n```\n\(activeCodeContent)\n```\nProvide explanations and generate code blocks. Keep code blocks complete so the user can easily copy or replace."
        
        db.generateGeminiResponseDirect(prompt: "\(systemContext)\n\nUser request: \(prompt)", history: codeChatMessages.dropLast()) { responseText in
            DispatchQueue.main.async {
                self.isCodeChatThinking = false
                if let reply = responseText {
                    let modelMsg = ChatMessage(role: "model", content: reply)
                    self.codeChatMessages.append(modelMsg)
                    
                    // Parse potential code blocks from response to auto-populate the editor!
                    if let codeBlock = extractFirstCodeBlock(from: reply) {
                        self.activeCodeContent = codeBlock.code
                        if let fileType = codeBlock.language {
                            let ext = fileType == "python" ? "py" : (fileType == "javascript" ? "js" : (fileType == "bash" ? "sh" : "py"))
                            self.activeCodeFile = "script.\(ext)"
                        }
                    }
                } else {
                    let errorMsg = ChatMessage(role: "model", content: "Error: Failed to fetch response from Gemini. Please verify connection.")
                    self.codeChatMessages.append(errorMsg)
                }
                triggerHaptic()
            }
        }
    }
    
    private func extractFirstCodeBlock(from text: String) -> (code: String, language: String?)? {
        guard let startRange = text.range(of: "```") else { return nil }
        let remainingText = text[startRange.upperBound...]
        
        // Find the end of the line containing language specifier
        guard let firstNewlineRange = remainingText.range(of: "\n") else { return nil }
        let language = String(remainingText[..<firstNewlineRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        let codeContentStart = remainingText[firstNewlineRange.upperBound...]
        guard let endRange = codeContentStart.range(of: "```") else { return nil }
        let code = String(codeContentStart[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        return (code, language.isEmpty ? nil : language)
    }
}


