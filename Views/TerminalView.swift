import SwiftUI

/// Developer and System Diagnostician Terminal - Redesigned with retro-futuristic CRT scanlines,
/// audio-synthesized keystrokes, dual themes (Cyber Matrix vs Amber Industrial), and stateful command parsing.
public struct TerminalView: View {
    @ObservedObject var db = FirestoreService.shared
    @StateObject private var engine = UnisonTerminalEngine()
    @State private var inputCmd = ""
    @State private var useAmberTheme = false
    @State private var playAudioFeedback = true
    
    public init() {}
    
    // Aesthetic theme pairings
    private var primaryColor: Color {
        useAmberTheme ? Color(red: 0.95, green: 0.55, blue: 0.05) : Color(red: 0.13, green: 0.85, blue: 0.35)
    }
    
    private var terminalBg: Color {
        Color.clear
    }
    
    public var body: some View {
        ZStack {
            // Retro Terminal Backplate
            terminalBg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - TERMINAL METADATA HEADER
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(primaryColor)
                            .frame(width: 6, height: 6)
                            .shimmeringEffect()
                        
                        Text("SECURE OPERATOR DIAGNOSTIC SHELL")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(primaryColor)
                        
                        Text("● LOCAL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(primaryColor.opacity(0.6))
                    }
                    Spacer()
                    
                    // Interactive Theme/Audio controls
                    HStack(spacing: 12) {
                        Button(action: {
                            useAmberTheme.toggle()
                            if playAudioFeedback { UnisonSoundEngine.shared.triggerBlip() }
                        }) {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 11))
                                .foregroundColor(primaryColor.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            playAudioFeedback.toggle()
                            if playAudioFeedback { UnisonSoundEngine.shared.triggerBlip() }
                        }) {
                            Image(systemName: playAudioFeedback ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 11))
                                .foregroundColor(primaryColor.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            engine.history.removeAll()
                            engine.appendLine("Console record buffer flushed cleanly.", type: .system)
                            if playAudioFeedback { UnisonSoundEngine.shared.triggerBlip() }
                        }) {
                            Text("FLUSH_BUFFER")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(primaryColor.opacity(0.15))
                                .foregroundColor(primaryColor)
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.35))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(primaryColor.opacity(0.15)),
                    alignment: .bottom
                )
                
                // MARK: - CORE TERMINAL LINE FEED
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(engine.history) { line in
                                HStack(alignment: .top, spacing: 6) {
                                    if line.type == .input {
                                        Text(">")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(primaryColor)
                                    }
                                    
                                    Text(line.text)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(textColorForType(line.type))
                                        .multilineTextAlignment(.leading)
                                        .textSelection(.enabled)
                                }
                                .id(line.id)
                            }
                            
                            // Real-time blinking cursor spacer
                            HStack(spacing: 4) {
                                Text("$ \(inputCmd)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(primaryColor)
                                
                                Rectangle()
                                    .fill(primaryColor)
                                    .frame(width: 6, height: 12)
                                    .blinkingEffect()
                            }
                            .id("BottomCursor")
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: engine.history.count) { _ in
                        withAnimation {
                            proxy.scrollTo("BottomCursor", anchor: .bottom)
                        }
                    }
                }
                
                // MARK: - KEYBOARD INPUT PANEL
                HStack(spacing: 12) {
                    Text("$")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundColor(primaryColor)
                    
                    TextField("Enter system instructions or 'help'...", text: $inputCmd, onCommit: {
                        dispatchCommand()
                    })
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(primaryColor)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
                    .onChange(of: inputCmd) { _ in
                        if playAudioFeedback {
                            UnisonSoundEngine.shared.triggerKeystrokeClick()
                        }
                    }
                    
                    Button(action: {
                        dispatchCommand()
                    }) {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(primaryColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.45))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(primaryColor.opacity(0.15)),
                    alignment: .top
                )
            }
            
            // MARK: - CRT SCANLINE SCREEN FILTER
            CRTScanlineOverlay(color: primaryColor)
                .allowsHitTesting(false)
        }
    }
    
    private func dispatchCommand() {
        let trimmed = inputCmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Execute through engine
        engine.runCommand(trimmed)
        
        // Audio Synthesizer Feedback
        if playAudioFeedback {
            if trimmed.lowercased() == "help" || trimmed.lowercased() == "ping" {
                UnisonSoundEngine.shared.triggerSuccess()
            } else {
                UnisonSoundEngine.shared.triggerBlip()
            }
        }
        
        inputCmd = ""
    }
    
    private func textColorForType(_ type: UnisonTerminalEngine.TerminalLine.LineType) -> Color {
        switch type {
        case .input:
            return primaryColor
        case .output:
            return primaryColor.opacity(0.9)
        case .success:
            return useAmberTheme ? Color(red: 0.98, green: 0.85, blue: 0.35) : Color(red: 0.35, green: 0.98, blue: 0.55)
        case .error:
            return Color.red
        case .system:
            return primaryColor.opacity(0.65)
        }
    }
}

// Retro CRT Monitor Scanline and Vignette filter
struct CRTScanlineOverlay: View {
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Repeating vertical or horizontal lines mimicking CRT grid phosphors
                VStack(spacing: 3) {
                    ForEach(0..<Int(geo.size.height/3), id: \.self) { _ in
                        Rectangle()
                            .fill(color.opacity(0.04))
                            .frame(height: 1)
                    }
                }
                
                // Corner vignette shading for retro screen curvature feel
                RadialGradient(
                    gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.55)]),
                    center: .center,
                    startRadius: geo.size.width * 0.35,
                    endRadius: geo.size.width * 0.75
                )
            }
        }
    }
}

// Custom View extensions for animated blinking and pulsing effects
extension View {
    func blinkingEffect() -> some View {
        self.modifier(BlinkingModifier())
    }
    
    func shimmeringEffect() -> some View {
        self.modifier(ShimmeringModifier())
    }
}

struct BlinkingModifier: ViewModifier {
    @State private var isVisible = true
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1.0 : 0.0)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isVisible.toggle()
                }
            }
    }
}

struct ShimmeringModifier: ViewModifier {
    @State private var isGlowing = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isGlowing ? 1.0 : 0.5)
            .scaleEffect(isGlowing ? 1.1 : 0.95)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isGlowing.toggle()
                }
            }
    }
}
