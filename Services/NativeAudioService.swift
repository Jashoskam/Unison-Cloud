import Foundation
import SwiftUI
import Combine
#if os(macOS)
import AppKit
import AVFoundation
#endif

@MainActor
public final class NativeAudioService: ObservableObject {
    public static let shared = NativeAudioService()

    @Published public var isEnabled: Bool = false
    @Published public var isPushToTalkEnabled: Bool = false
    @Published public var isListening: Bool = false
    @Published public var microphoneLevel: Float = 0.0
    @Published public var systemOutputLevel: Float = 0.0
    @Published public var lastTranscript: String = ""
    @Published public var statusMessage: String = "Audio loopback idle"

    private var cancellables = Set<AnyCancellable>()
    private var hotkeyMonitor: Any?

    private init() {
        bindSpeechRecognizer()
    }

    public func configure() {
        installGlobalHotkeyListener()
        statusMessage = "Voice engine ready"
    }

    public func startLoopback() {
        isEnabled = true
        statusMessage = "Loopback active"
        ScreenCaptureManager.shared.startPersistentCapture()
        SpeechRecognizer.shared.onSilenceDetected = { [weak self] transcript in
            self?.handleFinalTranscript(transcript)
        }
        SpeechRecognizer.shared.startListening()
        isListening = true
    }

    public func stopLoopback() {
        isEnabled = false
        isListening = false
        statusMessage = "Loopback stopped"
        SpeechRecognizer.shared.stopListening()
        ScreenCaptureManager.shared.stopPersistentCapture()
    }

    public func togglePushToTalk() {
        isPushToTalkEnabled.toggle()
        if isPushToTalkEnabled {
            configure()
            statusMessage = "Push-to-talk enabled"
        } else {
            statusMessage = "Push-to-talk disabled"
        }
    }

    public func startPushToTalkCapture() {
        guard isPushToTalkEnabled else { return }
        isListening = true
        statusMessage = "Listening"
        SpeechRecognizer.shared.onSilenceDetected = { [weak self] transcript in
            self?.handleFinalTranscript(transcript)
        }
        SpeechRecognizer.shared.startListening()
    }

    public func stopPushToTalkCapture() {
        isListening = false
        statusMessage = "Push-to-talk released"
        SpeechRecognizer.shared.stopListening()
    }

    private func bindSpeechRecognizer() {
        SpeechRecognizer.shared.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                self?.lastTranscript = transcript
            }
            .store(in: &cancellables)

        SpeechRecognizer.shared.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.microphoneLevel = level
            }
            .store(in: &cancellables)
    }

    private func handleFinalTranscript(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastTranscript = trimmed
        statusMessage = "Captured: \(trimmed)"
        isListening = false
    }

    private func installGlobalHotkeyListener() {
        guard hotkeyMonitor == nil else { return }
        #if os(macOS)
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return }
            let isPushHotkey = event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) && event.keyCode == 49
            guard self.isPushToTalkEnabled, isPushHotkey else { return }
            DispatchQueue.main.async {
                if event.type == .keyDown {
                    self.startPushToTalkCapture()
                } else if event.type == .keyUp {
                    self.stopPushToTalkCapture()
                }
            }
        }
        #endif
    }
}
