import SwiftUI
import Combine
import AVFoundation

/// Beautiful Modern Industrial SwiftUI Authentication and Pairing Interface
/// Translated directly from the high-fidelity Unison Web OS client.
public struct LoginView: View {
    @ObservedObject var db = FirestoreService.shared
    
    // MARK: - State properties translated from Login.tsx
    @State private var showingCopiedAlert = false
    @State private var copiedText: String? = nil
    
    // User custom authentication node settings
    @State private var emailInput = "jashoskamb@gmail.com"
    @State private var passwordInput = ""
    
    // Dynamic layout state matching the web's conditional rendering paths
    @State private var unauthorizedDomain = false
    @State private var pairCodeParam: String? = nil // e.g. "U-X7Y2" (Browser Handoff view trigger)
    @State private var nativePairingCode: String? = nil // e.g. "U-K9W4" (Native Pairing view trigger)
    @State private var isLoggingIn = false
    @State private var useRedirect = false
    @State private var error: String? = nil
    @State private var pairingSuccess = false
    @State private var isPairingLoading = false

    
    // --- ANIMATION TRACKERS FOR THE DYNAMIC MOVING BACKGROUND ---
    @State private var waveMovement = false
    @State private var bloomOffset1 = CGSize(width: -40, height: 60)
    @State private var bloomOffset2 = CGSize(width: 50, height: -30)
    @State private var bgHueRotation = 0.0
    
    // Dev Tools to easily preview all 4 states in Xcode Previews
    @State private var showDevTools = false
    
    public init() {}
    
    // MARK: - Calculated Centers (Prevents Type-Check Timeouts)
    private var greenGlowCenter: UnitPoint {
        let x = 0.2 + sin(bgHueRotation * .pi / 180.0) * 0.1
        let y = 0.8 + cos(bgHueRotation * .pi / 180.0) * 0.1
        return UnitPoint(x: x, y: y)
    }
    
    private var goldGlowCenter: UnitPoint {
        let x = 0.8 - cos(bgHueRotation * .pi / 180.0) * 0.15
        let y = 0.3 + sin(bgHueRotation * .pi / 180.0) * 0.1
        return UnitPoint(x: x, y: y)
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                HStack(spacing: 0) {
                    // Left Half: Blue Gradient Welcome View
                    leftWelcomeView
                        .frame(width: geometry.size.width * 0.5)
                    
                    // Right Half: Black Login Sign-In Form View
                    rightLoginFormView(geometry: geometry)
                        .frame(width: geometry.size.width * 0.5)
                        .background(Color.black)
                }
                
                // MARK: - Dev Tools Floating Menu
                if showDevTools {
                    devToolsMenu
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            withAnimation(.linear(duration: 25.0).repeatForever(autoreverses: false)) {
                bgHueRotation = 360.0
            }
        }
    }
    
    // MARK: - VIEW MODULES
    
    @ViewBuilder
    private var leftWelcomeView: some View {
        ZStack {
            // Animated Mesh Gradient Background
            MovingBlueMeshBackground()
            
            VStack(alignment: .leading, spacing: 0) {
                // Top header capsules
                HStack {
                    // Left capsule: Unison OS
                    HStack(spacing: 8) {
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Text("U")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        Text("Unison OS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12).background(.ultraThinMaterial))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    
                    Spacer()
                    
                    // Right capsule: Unison Ecosystem SSO
                    HStack(spacing: 6) {
                        Image(systemName: "key")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        Text("Unison Ecosystem SSO")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08).background(.ultraThinMaterial))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .padding(.top, 40)
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Welcome text block
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        Text("Welcome to")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Unison OS")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                            .overlay(
                                Rectangle()
                                    .fill(Color(red: 0.3, green: 0.85, blue: 1.0))
                                    .frame(height: 3)
                                    .offset(y: 6),
                                alignment: .bottomLeading
                            )
                    }
                    
                    Text("Part of the Unison parent platform. Sign in once with your Unison ID to access Unison OS, Unison Studio, Unison Code & all company apps seamlessly.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .lineSpacing(6)
                        .frame(maxWidth: 460)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Bottom capsules
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                        Text("Unison SSO Token")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08).background(.ultraThinMaterial))
                    .cornerRadius(12)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                        Text("Interactive Workspaces")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08).background(.ultraThinMaterial))
                    .cornerRadius(12)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text("Agentic AI & Systems")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08).background(.ultraThinMaterial))
                    .cornerRadius(12)
                }
                .padding(.bottom, 40)
                .padding(.horizontal, 40)
            }
        }
    }
    
    @ViewBuilder
    private func rightLoginFormView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    if unauthorizedDomain {
                        unauthorizedDomainView
                    } else if let pairCode = pairCodeParam {
                        browserHandoffView(pairCode: pairCode)
                    } else if let nativeCode = db.pairingCode ?? nativePairingCode {
                        nativePairingView(code: nativeCode)
                    } else {
                        signInFormLayout(geometry: geometry)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 40)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func signInFormLayout(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // UNISON SINGLE SIGN-ON key badge
            HStack(spacing: 6) {
                Image(systemName: "key")
                    .font(.system(size: 11))
                    .foregroundColor(.cyan)
                Text("UNISON SINGLE SIGN-ON")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.cyan.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
            )
            
            // Header text
            VStack(alignment: .leading, spacing: 8) {
                Text("Sign in with Unison ID")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text("One Unison account connects you to all apps across the Unison platform")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            // Segment selector
            HStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "key")
                        .font(.system(size: 11))
                    Text("Unison ID SSO")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.to.line.compact")
                        .font(.system(size: 11))
                    Text("Email Sign In")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white)
                .cornerRadius(8)
                
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 11))
                    Text("Sign Up")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .padding(4)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
            
            // Email Input
            VStack(alignment: .leading, spacing: 6) {
                Text("Unison Email")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)
                
                HStack(spacing: 12) {
                    Image(systemName: "envelope")
                        .foregroundColor(.gray)
                    TextField("user@unison.app", text: $emailInput)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                }
                .padding(12)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            
            // Password Input
            VStack(alignment: .leading, spacing: 6) {
                Text("Password")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)
                
                HStack(spacing: 12) {
                    Image(systemName: "lock")
                        .foregroundColor(.gray)
                    SecureField("••••••••", text: $passwordInput)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                }
                .padding(12)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            
            if let err = error {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            
            // Submit Button
            Button(action: {
                isLoggingIn = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    isLoggingIn = false
                    db.loginDirectly(email: emailInput)
                }
            }) {
                HStack {
                    Spacer()
                    if isLoggingIn {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text("SIGN IN WITH UNISON ID")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .tracking(1.0)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.vertical, 14)
                .background(
                    MovingButtonMeshBackground()
                )
                .cornerRadius(14)
                .shadow(color: Color.blue.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            
            // OR Divider
            HStack {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                Text("OR").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.2)).padding(.horizontal, 8)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
            .padding(.vertical, 8)
            
            // Google Button
            Button(action: {
                db.loginDirectly(email: "googleuser@unison.app")
            }) {
                HStack(spacing: 8) {
                    Spacer()
                    Text("G")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.red)
                    Text("Continue with Google")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // Supabase link
            HStack {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 11))
                    .foregroundColor(.purple)
                Text("Supabase Configuration & Project Keys")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.top, 16)
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        Color.black
            .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var footerView: some View {
        EmptyView()
    }
    
    @ViewBuilder
    private var devToolsMenu: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text("PREVIEW MANAGER")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    
                    Button("Mode 1: Sign In UI") {
                        unauthorizedDomain = false
                        pairCodeParam = nil
                        nativePairingCode = nil
                    }
                    
                    Button("Mode 2: Native Pairing") {
                        unauthorizedDomain = false
                        pairCodeParam = nil
                        nativePairingCode = "U-K9W4"
                    }
                    
                    Button("Mode 3: Browser App Handoff") {
                        unauthorizedDomain = false
                        pairCodeParam = "U-X7Y2"
                        nativePairingCode = nil
                    }
                    
                    Button("Mode 4: Blocked Domain Screen") {
                        unauthorizedDomain = true
                        pairCodeParam = nil
                        nativePairingCode = nil
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.85))
                .cornerRadius(12)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.cyan)
                .shadow(radius: 10)
                .padding(.trailing, 16)
            }
            Spacer()
        }
        .padding(.top, 140)
    }
    
    // MARK: - SCREEN 2: Native Side Device Verification Screen
    @ViewBuilder
    private func nativePairingView(code: String) -> some View {
        VStack(spacing: 20) {
            // Elegant top tracking line
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 14))
                        .foregroundColor(.cyan)
                    Text("DEVICE AUTH")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.45))
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 5, height: 5)
                    Text("PAIRING ACTIVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.cyan.opacity(0.08))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 6) {
                Text("Link Desktop Client")
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .tracking(0.5)
                
                Text("Pop-up redirects are restricted inside this container. Complete pairing by copying this link or scanning the QR code below.")
                    .font(.system(size: 11, design: .default))
                    .foregroundColor(.white.opacity(0.6))
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            
            // Procedural High-tech QR Code container
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 140, height: 140)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.cyan.opacity(0.25), lineWidth: 1)
                        )
                    
                    // Styled Procedural Vector QR Design
                    ProceduralQRGraphic()
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .square))
                        .frame(width: 100, height: 100)
                }
                .shadow(color: Color.cyan.opacity(0.12), radius: 15)
                
                Text("Scan with your mobile device")
                    .font(.system(size: 8, weight: .bold, design: .default))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.vertical, 10)
            
            // Code Banner
            VStack(spacing: 4) {
                Text("Pairing PIN Code")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(2.0)
                
                Text(code)
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .foregroundColor(.cyan)
                    .tracking(4.0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.02))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            // Manual Link trigger
            manualLinkField(code: code)
            
            // Launch verification directly button
            Button(action: {
                if let url = URL(string: "\(db.webUrl)/?pair=\(code)") {
                    #if os(iOS)
                    UIApplication.shared.open(url)
                    #endif
                }
            }) {
                HStack(spacing: 8) {
                    Text("Launch verification page")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11, weight: .bold, design: .default))
                .tracking(1.0)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.cyan.opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.top, 8)
            
            // Waiting pulse diagnostic line
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    .scaleEffect(0.7)
                Text("Waiting for mobile/tab authorization...")
                    .font(.system(size: 9, weight: .bold, design: .default))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.vertical, 4)
            
            // Back button
            Button(action: {
                withAnimation(.spring()) {
                    nativePairingCode = nil
                }
            }) {
                Text("Go Back")
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.top, 4)
        }
        .padding(24)
        .background(Color.black)
        .cornerRadius(32)
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
    
    @ViewBuilder
    private func manualLinkField(code: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Copy Link manually")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.0)
            
            let linkString = "\(db.webUrl)/?pair=\(code)"
            
            HStack {
                Text(linkString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.cyan)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    copyToPasteboard(linkString)
                    copiedText = linkString
                    showingCopiedAlert = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedText = nil
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedText == linkString ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copiedText == linkString ? "COPIED" : "COPY")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    // MARK: - SCREEN 3: Browser Side Handoff Screen
    @ViewBuilder
    private func browserHandoffView(pairCode: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "tv")
                .font(.system(size: 40))
                .foregroundColor(.blue)
                .shadow(color: .blue.opacity(0.5), radius: 10)
                
            VStack(spacing: 6) {
                Text("Authorize Desktop Client")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text("A native Unison desktop app is requesting secure node linkage.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            
            // PIN Badge Card
            VStack(spacing: 4) {
                Text("Confirmation PIN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(1.5)
                
                Text(pairCode)
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1.0))
                    .tracking(4.0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.03))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            // Active Signed In User status
            VStack(spacing: 4) {
                Text("Signed-in Active Profile")
                    .font(.system(size: 8, weight: .bold, design: .default))
                    .tracking(1.5)
                    .foregroundColor(.green)
                
                Text("user@unison.os")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.green.opacity(0.06))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.green.opacity(0.25), lineWidth: 1)
            )
            
            if pairingSuccess {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("Authentication Shared")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text("Your desktop instance has authorized successfully. You can close this view.")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 12) {
                    Button(action: {
                        isPairingLoading = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isPairingLoading = false
                            pairingSuccess = true
                        }
                    }) {
                        HStack {
                            if isPairingLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Approve Linkage")
                            }
                        }
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.blue.opacity(0.25))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Button("Decline Request") {
                        withAnimation {
                            pairCodeParam = nil
                        }
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(28)
        .background(Color.black)
        .cornerRadius(32)
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
    
    // MARK: - SCREEN 4: Unauthorized Domain Error Panel
    @ViewBuilder
    private var unauthorizedDomainView: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.alert")
                .font(.system(size: 44))
                .foregroundColor(.amberDark)
                .shadow(color: .amberDark.opacity(0.4), radius: 10)
                
            VStack(spacing: 4) {
                Text("Domain Authorization Needed")
                    .font(.system(size: 16, weight: .bold, design: .default))
                    .tracking(1.0)
                    .foregroundColor(.amberLight)
                Text("Your Supabase Project restricts access to registered origins. Register these domains to allow sign-in.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 8)
            
            // Domain Listing blocks with dynamic clipboard copy
            domainListingGroup
            
            // Helpful textual setup map
            navigationSetupMap
            
            // Console Button
            Button(action: {
                if let url = URL(string: "https://supabase.com/dashboard") {
                    #if os(iOS)
                    UIApplication.shared.open(url)
                    #endif
                }
            }) {
                HStack {
                    Text("Navigate to Settings Tab")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.amberDark.opacity(0.15))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.amberDark.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            
            Button("Go Back & Retry") {
                withAnimation {
                    unauthorizedDomain = false
                }
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white.opacity(0.4))
        }
        .padding(24)
        .background(Color.black)
        .cornerRadius(32)
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(Color.amberDark.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
    
    @ViewBuilder
    private var domainListingGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Copy these domains:")
                .font(.system(size: 9, weight: .bold, design: .default))
                .tracking(2.0)
                .foregroundColor(.white.opacity(0.5))
            
            let domain1 = db.webUrl.replacingOccurrences(of: "https://", with: "")
            
            HStack {
                Text(domain1)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    copyToPasteboard(domain1)
                    copiedText = domain1
                    showingCopiedAlert = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedText = nil
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedText == domain1 ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copiedText == domain1 ? "Copied" : "Copy")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    private var navigationSetupMap: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Visual Navigation Map")
                .font(.system(size: 9, weight: .bold))
                .tracking(2.0)
                .foregroundColor(.amberLight)
            
            Group {
                Text("1. Click \"Navigate to Settings Tab\" directly to load console.")
                Text("2. Beside 'Users' tab, select the \"Settings\" tab.")
                Text("3. On left sidebar, select \"Authorized domains\".")
                Text("4. Click \"Add domain\" & Paste copied origin.")
            }
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.75))
            .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .cornerRadius(16)
    }
    
    // Multi-platform safe clipboard pipeline
    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Color Extension for Premium Color Tones
extension Color {
    static let amberDark = Color(red: 0.95, green: 0.60, blue: 0.15)
    static let amberLight = Color(red: 1.0, green: 0.75, blue: 0.3)
}

// MARK: - Beautiful Custom Vector Interlocking Loop Logo
struct UnisonLogoView: View {
    var body: some View {
        ZStack {
            if let nsImg = NSImage(contentsOfFile: "/Users/jashoskam/Desktop/Unison-ES/Unison/appLogo.png") {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 68, height: 68)
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            } else {
                // Elegant white squircle container
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 68, height: 68)
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                
                // Vector path representing the sleek interlocking ribbon (the "U/S" loop)
                InterlockingLoopPath()
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 4.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 28, height: 36)
            }
        }
    }
}

/// Draws the precise organic loop ribbon path seen in the Unison branding.
struct InterlockingLoopPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Starting at the top-left loop curve down, crossing under, looping around the right
        path.move(to: CGPoint(x: w * 0.22, y: h * 0.15))
        
        // Left loop descending
        path.addCurve(
            to: CGPoint(x: w * 0.22, y: h * 0.55),
            control1: CGPoint(x: w * 0.05, y: h * 0.15),
            control2: CGPoint(x: w * 0.05, y: h * 0.55)
        )
        
        // Curve passing over to the right side
        path.addCurve(
            to: CGPoint(x: w * 0.78, y: h * 0.45),
            control1: CGPoint(x: w * 0.35, y: h * 0.85),
            control2: CGPoint(x: w * 0.65, y: h * 0.15)
        )
        
        // Right loop ascending & returning down
        path.addCurve(
            to: CGPoint(x: w * 0.78, y: h * 0.85),
            control1: CGPoint(x: w * 0.95, y: h * 0.45),
            control2: CGPoint(x: w * 0.95, y: h * 0.85)
        )
        
        // Bottom sweep crossing back to meet the left track
        path.addCurve(
            to: CGPoint(x: w * 0.22, y: h * 0.15),
            control1: CGPoint(x: w * 0.65, y: h * 0.95),
            control2: CGPoint(x: w * 0.35, y: h * 0.15)
        )
        
        return path
    }
}

// MARK: - Cyber Procedural QR Graphic Vector Shape
struct ProceduralQRGraphic: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // --- ANCHOR BOX 1: Top-Left ---
        path.addRect(CGRect(x: 0, y: 0, width: w * 0.3, height: h * 0.3))
        path.addRect(CGRect(x: w * 0.08, y: h * 0.08, width: w * 0.14, height: h * 0.14))
        
        // --- ANCHOR BOX 2: Top-Right ---
        path.addRect(CGRect(x: w * 0.7, y: 0, width: w * 0.3, height: h * 0.3))
        path.addRect(CGRect(x: w * 0.78, y: h * 0.08, width: w * 0.14, height: h * 0.14))
        
        // --- ANCHOR BOX 3: Bottom-Left ---
        path.addRect(CGRect(x: 0, y: h * 0.7, width: w * 0.3, height: h * 0.3))
        path.addRect(CGRect(x: w * 0.08, y: h * 0.78, width: w * 0.14, height: h * 0.14))
        
        // --- RANDOM TECH CHIPS/PIXELS ---
        // Center blocks
        path.addRect(CGRect(x: w * 0.45, y: h * 0.45, width: w * 0.1, height: h * 0.1))
        path.addRect(CGRect(x: w * 0.35, y: h * 0.35, width: w * 0.08, height: h * 0.15))
        path.addRect(CGRect(x: w * 0.55, y: h * 0.35, width: w * 0.1, height: h * 0.08))
        path.addRect(CGRect(x: w * 0.4, y: h * 0.6, width: w * 0.18, height: h * 0.08))
        
        // Dispersed side nodes
        path.addRect(CGRect(x: w * 0.75, y: h * 0.45, width: w * 0.15, height: h * 0.1))
        path.addRect(CGRect(x: w * 0.85, y: h * 0.6, width: w * 0.08, height: h * 0.15))
        path.addRect(CGRect(x: w * 0.45, y: h * 0.12, width: w * 0.12, height: h * 0.08))
        path.addRect(CGRect(x: w * 0.15, y: h * 0.45, width: w * 0.1, height: h * 0.12))
        
        return path
    }
}

// MARK: - Elegant Interaction Feedback Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct LoginView_Previews_Updated: PreviewProvider {
    static var previews: some View {
        LoginView()
            .preferredColorScheme(.dark)
    }
}

// MARK: - Native Background Video Loops (1:1 with Web client properties)
#if os(macOS)
struct MacBackgroundVideoView: NSViewRepresentable {
    let urlString: String
    
    func makeNSView(context: Context) -> NSView {
        let view = AVPlayerViewContainer()
        view.wantsLayer = true
        
        guard let url = URL(string: urlString) else { return view }
        context.coordinator.setupPlayer(url: url, in: view)
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layout()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class AVPlayerViewContainer: NSView {
        private var playerLayer: AVPlayerLayer?
        
        func setupLayer(_ layer: AVPlayerLayer) {
            self.playerLayer?.removeFromSuperlayer()
            self.playerLayer = layer
            self.layer?.addSublayer(layer)
        }
        
        override func layout() {
            super.layout()
            playerLayer?.frame = bounds
        }
    }
    
    class Coordinator: NSObject {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        
        func setupPlayer(url: URL, in container: AVPlayerViewContainer) {
            let asset = AVAsset(url: url)
            let playerItem = AVPlayerItem(asset: asset)
            
            let queuePlayer = AVQueuePlayer(playerItem: playerItem)
            queuePlayer.isMuted = true
            self.player = queuePlayer
            
            let playerLayer = AVPlayerLayer(player: queuePlayer)
            playerLayer.videoGravity = .resizeAspectFill
            container.setupLayer(playerLayer)
            
            // Smooth, hardware-accelerated looping of exactly 6.0 seconds matching the Web client
            let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 6.0, preferredTimescale: 600))
            self.looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem, timeRange: range)
            
            queuePlayer.play()
        }
    }
}
#else
struct iOSBackgroundVideoView: UIViewRepresentable {
    let urlString: String
    
    func makeUIView(context: Context) -> UIView {
        let view = AVPlayerUIViewContainer()
        
        guard let url = URL(string: urlString) else { return view }
        context.coordinator.setupPlayer(url: url, in: view)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class AVPlayerUIViewContainer: UIView {
        private var playerLayer: AVPlayerLayer?
        
        func setupLayer(_ layer: AVPlayerLayer) {
            self.playerLayer?.removeFromSuperlayer()
            self.playerLayer = layer
            self.layer.addSublayer(layer)
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer?.frame = bounds
        }
    }
    
    class Coordinator: NSObject {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        
        func setupPlayer(url: URL, in container: AVPlayerUIViewContainer) {
            let asset = AVAsset(url: url)
            let playerItem = AVPlayerItem(asset: asset)
            
            let queuePlayer = AVQueuePlayer(playerItem: playerItem)
            queuePlayer.isMuted = true
            self.player = queuePlayer
            
            let playerLayer = AVPlayerLayer(player: queuePlayer)
            playerLayer.videoGravity = .resizeAspectFill
            container.setupLayer(playerLayer)
            
            // Smooth, hardware-accelerated looping of exactly 6.0 seconds matching the Web client
            let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 6.0, preferredTimescale: 600))
            self.looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem, timeRange: range)
            
            queuePlayer.play()
        }
    }
}
#endif

// MARK: - MOVING MESH GRADIENT BACKGROUND
struct MovingMeshGradientBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Gradient base using violet
            hexColor("7E53CE")
            
            // Mesh circle 1: #F3E8FA (Lavender Light)
            Circle()
                .fill(hexColor("F3E8FA"))
                .frame(width: 160, height: 160)
                .blur(radius: 20)
                .offset(x: animate ? -40 : 40, y: animate ? -20 : 20)
                .scaleEffect(animate ? 1.2 : 0.8)
            
            // Mesh circle 2: #88BAEC (Sky Blue)
            Circle()
                .fill(hexColor("88BAEC"))
                .frame(width: 170, height: 170)
                .blur(radius: 22)
                .offset(x: animate ? 50 : -50, y: animate ? 30 : -30)
                .scaleEffect(animate ? 0.85 : 1.25)
            
            // Mesh circle 3: #758DEC (Cornflower Blue)
            Circle()
                .fill(hexColor("758DEC"))
                .frame(width: 130, height: 130)
                .blur(radius: 18)
                .offset(x: animate ? -20 : 30, y: animate ? 40 : -40)
                .scaleEffect(animate ? 1.1 : 0.75)
                
            // Mesh circle 4: #9183E0 (Medium Lavender)
            Circle()
                .fill(hexColor("9183E0"))
                .frame(width: 150, height: 150)
                .blur(radius: 20)
                .offset(x: animate ? 30 : -25, y: animate ? -35 : 35)
                .scaleEffect(animate ? 0.9 : 1.15)
                
            // Mesh circle 5: #E6E5FA (Light Periwinkle)
            Circle()
                .fill(hexColor("E6E5FA"))
                .frame(width: 140, height: 140)
                .blur(radius: 18)
                .offset(x: animate ? -35 : 35, y: animate ? 15 : -15)
                .scaleEffect(animate ? 1.15 : 0.8)
                
            // Mesh circle 6: #827BDD (Soft Blue-Violet)
            Circle()
                .fill(hexColor("827BDD"))
                .frame(width: 120, height: 120)
                .blur(radius: 15)
                .offset(x: animate ? 10 : -20, y: animate ? -30 : 25)
                .scaleEffect(animate ? 0.8 : 1.2)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 5.0)
                .repeatForever(autoreverses: true)
            ) {
                animate = true
            }
        }
    }
}

fileprivate func hexColor(_ hex: String) -> Color {
    Color(hex: hex) ?? .indigo
}

struct MovingBlueMeshBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Gradient base using deep blue
            Color(red: 0.02, green: 0.15, blue: 0.45)
            
            // Mesh circle 1: Bright Cyan
            Circle()
                .fill(Color(red: 0.0, green: 0.85, blue: 1.0))
                .frame(width: 320, height: 320)
                .blur(radius: 40)
                .offset(x: animate ? -100 : 80, y: animate ? -60 : 40)
                .scaleEffect(animate ? 1.3 : 0.8)
            
            // Mesh circle 2: Sky Blue
            Circle()
                .fill(Color(red: 0.0, green: 0.65, blue: 1.0))
                .frame(width: 350, height: 350)
                .blur(radius: 45)
                .offset(x: animate ? 120 : -90, y: animate ? 70 : -80)
                .scaleEffect(animate ? 0.85 : 1.25)
            
            // Mesh circle 3: Royal Blue
            Circle()
                .fill(Color(red: 0.1, green: 0.35, blue: 0.85))
                .frame(width: 300, height: 300)
                .blur(radius: 35)
                .offset(x: animate ? -60 : 70, y: animate ? 90 : -70)
                .scaleEffect(animate ? 1.2 : 0.75)
                
            // Mesh circle 4: Indigo
            Circle()
                .fill(Color(red: 0.15, green: 0.25, blue: 0.75))
                .frame(width: 330, height: 330)
                .blur(radius: 40)
                .offset(x: animate ? 80 : -75, y: animate ? -95 : 95)
                .scaleEffect(animate ? 0.95 : 1.15)
                
            // Mesh circle 5: Teal/Turquoise
            Circle()
                .fill(Color(red: 0.0, green: 0.9, blue: 0.75))
                .frame(width: 280, height: 280)
                .blur(radius: 35)
                .offset(x: animate ? -95 : 85, y: animate ? 35 : -45)
                .scaleEffect(animate ? 1.15 : 0.85)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 8.0)
                .repeatForever(autoreverses: true)
            ) {
                animate = true
            }
        }
    }
}

struct MovingButtonMeshBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Gradient base: deep blue
            Color(red: 0.05, green: 0.3, blue: 0.6)
            
            // Mesh circle 1: Cyan
            Circle()
                .fill(Color(red: 0.0, green: 0.8, blue: 1.0))
                .frame(width: 100, height: 100)
                .blur(radius: 12)
                .offset(x: animate ? -30 : 20, y: animate ? -10 : 15)
                .scaleEffect(animate ? 1.2 : 0.8)
            
            // Mesh circle 2: Sky Blue
            Circle()
                .fill(Color(red: 0.2, green: 0.6, blue: 0.9))
                .frame(width: 120, height: 120)
                .blur(radius: 15)
                .offset(x: animate ? 30 : -25, y: animate ? 15 : -20)
                .scaleEffect(animate ? 0.85 : 1.25)
            
            // Mesh circle 3: Vibrant Teal
            Circle()
                .fill(Color(red: 0.0, green: 0.85, blue: 0.7))
                .frame(width: 90, height: 90)
                .blur(radius: 12)
                .offset(x: animate ? -15 : 25, y: animate ? 25 : -25)
                .scaleEffect(animate ? 1.15 : 0.75)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 3.5)
                .repeatForever(autoreverses: true)
            ) {
                animate = true
            }
        }
    }
}


