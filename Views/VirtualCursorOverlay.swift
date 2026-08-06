import SwiftUI
#if os(macOS)
import AppKit
#endif
import Combine

#if os(macOS)
// Borderless always-on-top overlay window for the separate virtual cursor experience.
public class VisualOverlayWindow: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isFloatingPanel = true
        self.tabbingMode = .disallowed
        self.alphaValue = 1.0
        self.isMovableByWindowBackground = false
    }
    
    override public var canBecomeKey: Bool { return false }
    override public var canBecomeMain: Bool { return false }
}
#endif

public struct RunningAppInfo: Identifiable, Hashable {
    public var id: String { bundleIdentifier ?? name }
    public let name: String
    public let bundleIdentifier: String?
    public let processIdentifier: Int32
}

public class VirtualCursorManager: ObservableObject {
    public static let shared = VirtualCursorManager()
    
    public let objectWillChange = ObservableObjectPublisher()
    
    @Published public var cursorPosition: CGPoint = CGPoint(x: 500, y: 500)
    @Published public var isHovering: Bool = false
    @Published public var isClicking: Bool = false
    @Published public var isVisible: Bool = false
    @Published public var pressedKey: String? = nil
    @Published public var activeDemoPrompt: String? = nil
    @Published public var activeDemoMode: String? = nil
    
    @Published public var currentActionStatus: String? = nil
    @Published public var targetWindowFrame: NSRect? = nil
    @Published public var highlightTargetApp: Bool = true
    
    @Published public var selectedTargetApp: RunningAppInfo? = nil {
        didSet {
            #if os(macOS)
            if selectedTargetApp != nil {
                startTrackingTargetApp()
            } else {
                stopTrackingTargetApp()
            }
            #endif
        }
    }
    
    #if os(macOS)
    private var appFrameTimer: Timer?
    
    public func startTrackingTargetApp() {
        appFrameTimer?.invalidate()
        appFrameTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self, let app = self.selectedTargetApp else { return }
            DispatchQueue.main.async {
                if let bundleId = app.bundleIdentifier,
                   let frame = VisualOverlayWindowController.windowFrame(forAppBundleIdentifier: bundleId) {
                    self.targetWindowFrame = frame
                } else {
                    self.targetWindowFrame = nil
                }
            }
        }
    }
    
    public func stopTrackingTargetApp() {
        appFrameTimer?.invalidate()
        appFrameTimer = nil
        targetWindowFrame = nil
    }
    
    public static func getRunningApps() -> [RunningAppInfo] {
        let apps = NSWorkspace.shared.runningApplications
        return apps.filter { $0.activationPolicy == .regular && !($0.localizedName ?? "").isEmpty }
            .map { RunningAppInfo(name: $0.localizedName ?? "Unknown", bundleIdentifier: $0.bundleIdentifier, processIdentifier: $0.processIdentifier) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    #else
    public static func getRunningApps() -> [RunningAppInfo] {
        return []
    }
    #endif
    
    private var animationTimer: Timer?
    private var currentPathPoints: [CGPoint] = []
    private var currentStep = 0
    private let totalSteps = 45 // ~0.75 seconds animate at 60fps
    
    private init() {}
    
    public func calculateBezierPath(from: CGPoint, to: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: from)
        // Calculate randomized control points to simulate natural movement
        let control1 = CGPoint(x: from.x + (to.x - from.x) * 0.25, y: from.y + (to.y - from.y) * 0.1)
        let control2 = CGPoint(x: from.x + (to.x - from.x) * 0.75, y: from.y + (to.y - from.y) * 0.9)
        path.addCurve(to: to, control1: control1, control2: control2)
        return path
    }
    
    public func runOperatorDemo(prompt: String, mode: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        activeDemoPrompt = trimmedPrompt.isEmpty ? "Open Calculator and type 42" : trimmedPrompt
        activeDemoMode = mode
        isVisible = true
        isHovering = true
        isClicking = false
        pressedKey = nil
        
        #if os(macOS)
        VisualOverlayWindowController.shared.show()
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let firstPoint = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
        let secondPoint = CGPoint(x: screenFrame.midX + 180, y: screenFrame.midY - 180)
        
        animateTo(targetPoint: firstPoint)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.isClicking = true
            EventSynthesizer.shared.postClick(at: firstPoint)
            self.animateTo(targetPoint: secondPoint)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.isClicking = false
                self.isHovering = false
                self.pressedKey = "A"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    self.pressedKey = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                    self.pressedKey = "B"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    self.pressedKey = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    self.activeDemoPrompt = nil
                    self.activeDemoMode = nil
                }
            }
        }
        #endif
    }
    
    public func animateTo(targetPoint: CGPoint) {
        let start = cursorPosition
        let c1 = CGPoint(x: start.x + (targetPoint.x - start.x) * 0.25, y: start.y + (targetPoint.y - start.y) * 0.1)
        let c2 = CGPoint(x: start.x + (targetPoint.x - start.x) * 0.75, y: start.y + (targetPoint.y - start.y) * 0.9)
        
        currentPathPoints = []
        for i in 0...totalSteps {
            let t = CGFloat(i) / CGFloat(totalSteps)
            let x = pow(1-t, 3) * start.x + 3 * pow(1-t, 2) * t * c1.x + 3 * (1-t) * pow(t, 2) * c2.x + pow(t, 3) * targetPoint.x
            let y = pow(1-t, 3) * start.y + 3 * pow(1-t, 2) * t * c1.y + 3 * (1-t) * pow(t, 2) * c2.y + pow(t, 3) * targetPoint.y
            currentPathPoints.append(CGPoint(x: x, y: y))
        }
        
        currentStep = 0
        animationTimer?.invalidate()
        let newTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.currentStep < self.currentPathPoints.count {
                    withAnimation(.linear(duration: 1.0 / 60.0)) {
                        self.cursorPosition = self.currentPathPoints[self.currentStep]
                    }
                    self.currentStep += 1
                } else {
                    self.cursorPosition = targetPoint
                    timer.invalidate()
                }
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        self.animationTimer = newTimer
    }
}

struct KeyboardKeyView: View {
    let key: String
    let isPressed: Bool
    
    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(isPressed ? Color.black : Color.white)
            .frame(width: 24, height: 24)
            .background(isPressed ? Color.green : Color.white.opacity(0.05))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isPressed ? Color.green : Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.green, radius: isPressed ? 8 : 0)
            .scaleEffect(isPressed ? 0.9 : 1.0)
    }
}

struct FloatingKeyboardView: View {
    let pressedKey: String?
    
    let rows = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]
    
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("INTEGRATED AI KEYBOARD")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(Color.green.opacity(0.8))
                }
                Spacer()
                Circle()
                    .fill(pressedKey != nil ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .shadow(color: .green, radius: pressedKey != nil ? 4 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 5) {
                    ForEach(rows[rowIndex], id: \.self) { key in
                        let isPressed = pressedKey?.uppercased() == key.uppercased()
                        KeyboardKeyView(key: key, isPressed: isPressed)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.85))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.6), radius: 15, x: 0, y: 8)
    }
}

public struct VirtualCursorOverlayView: View {
    @ObservedObject var cursorManager = VirtualCursorManager.shared
    
    @State private var rippleScale: CGFloat = 0.0
    @State private var rippleOpacity: Double = 0.0
    @State private var secondRippleScale: CGFloat = 0.0
    @State private var borderPulseScale: CGFloat = 1.0
    @State private var radarPulseScale: CGFloat = 1.0
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear
                
                // 1. Plain White Sheet Overlay strictly over target application window
                if cursorManager.highlightTargetApp, let frame = cursorManager.targetWindowFrame {
                    ZStack {
                        // Plain white backdrop sheet
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.92))
                        
                        // Subtle inner border and status banner
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("UNISON AUTOMATION SHEET")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.black.opacity(0.75))
                            }
                            Text("Operating target application in background")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.black.opacity(0.45))
                        }
                    }
                    .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.minX + frame.width / 2.0, y: frame.minY + frame.height / 2.0)
                    .transition(.opacity)
                }
                
                // 2. Active Agent Prompt Banner at top left
                if let prompt = cursorManager.activeDemoPrompt, let mode = cursorManager.activeDemoMode {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.cyan)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.uppercased())
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundColor(.cyan)
                            Text(prompt)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                    )
                    .padding(20)
                }
                
                // 3. Intent-Based Animated Cursor & Target Click Point Overlay
                if cursorManager.isVisible {
                    ZStack(alignment: .topLeading) {
                        // A. Intent Reticle / Target Coordinate Ring
                        ZStack {
                            Circle()
                                .stroke(Color.cyan.opacity(0.7), lineWidth: 1.5)
                                .frame(width: 28, height: 28)
                            
                            // Precision crosshair lines
                            Rectangle()
                                .fill(Color.cyan.opacity(0.8))
                                .frame(width: 1, height: 8)
                            Rectangle()
                                .fill(Color.cyan.opacity(0.8))
                                .frame(width: 8, height: 1)
                            
                            // Center hotspot dot
                            Circle()
                                .fill(cursorManager.isClicking ? Color.green : Color.cyan)
                                .frame(width: 5, height: 5)
                        }
                        .position(x: cursorManager.cursorPosition.x, y: cursorManager.cursorPosition.y)
                        
                        // B. Target Coordinates Badge
                        HStack(spacing: 4) {
                            Image(systemName: "scope")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.cyan)
                            Text("(\(Int(cursorManager.cursorPosition.x)), \(Int(cursorManager.cursorPosition.y)))")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.cyan.opacity(0.4), lineWidth: 0.75)
                        )
                        .position(x: cursorManager.cursorPosition.x, y: max(18, cursorManager.cursorPosition.y - 26))
                        
                        // C. Radar Pulse Ring Underlay
                        Circle()
                            .stroke(Color.cyan.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 32, height: 32)
                            .scaleEffect(radarPulseScale)
                            .opacity(2.0 - radarPulseScale)
                            .position(x: cursorManager.cursorPosition.x, y: cursorManager.cursorPosition.y)
                        
                        // D. Color-Coded Click Event Feedback Animations (Primary Emerald & Secondary Cyan Ripples)
                        ZStack {
                            // Primary Emerald Click Ripple
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.green, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                                .frame(width: 60 * rippleScale, height: 60 * rippleScale)
                                .opacity(rippleOpacity)
                            
                            // Secondary Outer Glow Ring
                            Circle()
                                .stroke(Color.green.opacity(0.6), lineWidth: 1.5)
                                .frame(width: 80 * secondRippleScale, height: 80 * secondRippleScale)
                                .opacity(rippleOpacity * 0.7)
                        }
                        .position(x: cursorManager.cursorPosition.x, y: cursorManager.cursorPosition.y)
                        
                        // E. Animated Cursor Arrow & Status Badge
                        HStack(spacing: 6) {
                            ZStack {
                                Image(systemName: "cursorarrow.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.black.opacity(0.6))
                                    .offset(x: 1.5, y: 1.5)
                                    .blur(radius: 1)
                                
                                Image(systemName: "cursorarrow.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(cursorManager.isClicking ? .green : .white)
                                    .overlay(
                                        Image(systemName: "cursorarrow")
                                            .font(.system(size: 20))
                                            .foregroundColor(cursorManager.isClicking ? .green : .cyan)
                                    )
                            }
                            .scaleEffect(cursorManager.isClicking ? 0.8 : 1.0)
                            
                            // Color-Coded Action Status Badge
                            if let actionStatus = cursorManager.currentActionStatus {
                                HStack(spacing: 4) {
                                    if cursorManager.isClicking {
                                        Image(systemName: "hand.tap.fill")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.green)
                                    }
                                    Text(actionStatus)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(cursorManager.isClicking ? Color.green.opacity(0.85) : Color.black.opacity(0.8))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(cursorManager.isClicking ? Color.green : Color.white.opacity(0.2), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .position(x: cursorManager.cursorPosition.x + 8, y: cursorManager.cursorPosition.y + 12)
                    }
                    
                    // Keyboard typing indicator at bottom
                    VStack {
                        Spacer()
                        if cursorManager.pressedKey != nil {
                            FloatingKeyboardView(pressedKey: cursorManager.pressedKey)
                                .padding(.bottom, 30)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(width: geometry.size.width)
                }
            }
            .edgesIgnoringSafeArea(.all)
            .onChange(of: cursorManager.isClicking) { isClicking in
                if isClicking {
                    rippleScale = 0.1
                    secondRippleScale = 0.1
                    rippleOpacity = 1.0
                    withAnimation(.easeOut(duration: 0.45)) {
                        rippleScale = 1.0
                        rippleOpacity = 0.0
                    }
                    withAnimation(.easeOut(duration: 0.6).delay(0.08)) {
                        secondRippleScale = 1.0
                    }
                }
            }
            .onAppear {
                cursorManager.isVisible = true
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    borderPulseScale = 1.08
                }
                withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    radarPulseScale = 1.7
                }
            }
        }
    }
}


#if os(macOS)
public class VisualOverlayWindowController {
    public static let shared = VisualOverlayWindowController()
    public var window: VisualOverlayWindow?
    
    private init() {}
    
    public func show(forAppBundleIdentifier bundleIdentifier: String? = nil) {
        let contentRect: NSRect
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            contentRect = screen.frame
        } else {
            contentRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        }

        show(in: contentRect)

        if let bundleId = bundleIdentifier {
            if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
                VirtualCursorManager.shared.selectedTargetApp = RunningAppInfo(
                    name: runningApp.localizedName ?? "Target App",
                    bundleIdentifier: bundleId,
                    processIdentifier: runningApp.processIdentifier
                )
            }
        }
    }

    public func show(in contentRect: NSRect) {
        if let existing = window {
            existing.setFrame(contentRect, display: true)
            existing.orderFrontRegardless()
            VirtualCursorManager.shared.isVisible = true
            return
        }

        let overlayWindow = VisualOverlayWindow(contentRect: contentRect)
        overlayWindow.ignoresMouseEvents = true
        let hostingView = NSHostingView(rootView: VirtualCursorOverlayView())
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = NSRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height)
        overlayWindow.contentView = hostingView
        overlayWindow.setFrame(contentRect, display: true)
        overlayWindow.orderFrontRegardless()
        overlayWindow.level = .screenSaver
        self.window = overlayWindow
        VirtualCursorManager.shared.isVisible = true
        VirtualCursorManager.shared.cursorPosition = CGPoint(x: contentRect.width / 2.0, y: contentRect.height / 2.0)
    }

    public static func windowFrame(forAppBundleIdentifier bundleIdentifier: String) -> NSRect? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return nil
        }
        let pid = app.processIdentifier
        let options: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int, windowPID == pid else {
                continue
            }
            guard let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else {
                continue
            }
            guard width > 0, height > 0 else { continue }
            if let layer = windowInfo[kCGWindowLayer as String] as? Int, layer != 0 {
                continue
            }
            return NSRect(x: x, y: y, width: width, height: height)
        }

        return nil
    }
    
    public func hide() {
        window?.orderOut(nil)
        window = nil
        VirtualCursorManager.shared.isVisible = false
        VirtualCursorManager.shared.selectedTargetApp = nil
        VirtualCursorManager.shared.currentActionStatus = nil
    }
}
#else
public class VisualOverlayWindowController {
    public static let shared = VisualOverlayWindowController()
    private init() {}
    public func show() {}
    public func hide() {}
}
#endif
