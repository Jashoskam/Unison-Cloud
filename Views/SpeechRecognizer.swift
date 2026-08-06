import Foundation
import AVFoundation
import Speech
import Combine

/// SpeechRecognizer - A state-of-the-art native iOS speech processing engine
/// handling real-time continuous dictation (Advanced STT), background hotword detection,
/// automatic speech pickup (Auto Speech Up via silence-based VAD), and decibel metering.
public class SpeechRecognizer: ObservableObject {
    public static let shared = SpeechRecognizer()
    
    @Published public var transcript: String = ""
    @Published public var isListening: Bool = false
    @Published public var isHotwordActive: Bool = false
    @Published public var audioLevel: Float = 0.0
    @Published public var autoSpeechUpEnabled: Bool = true // Auto-submit on silence
    @Published public var errorMessage: String? = nil
    @Published public var isHotwordModeEnabled: Bool = false {
        didSet {
            DispatchQueue.main.async {
                if self.isHotwordModeEnabled {
                    if !self.isHotwordActive {
                        self.startHotwordDetection()
                    }
                } else {
                    if self.isHotwordActive {
                        self.stopListening()
                        self.isHotwordActive = false
                    }
                }
            }
        }
    }
    
    public var onHotwordDetected: (() -> Void)?
    public var onSilenceDetected: ((String) -> Void)?
    
    // Use a single persistent audio engine to avoid deallocation thread race crashes in CoreAudio
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioQueue = DispatchQueue(label: "com.unison.audioBufferQueue")
    
    private var silenceDetectionTimer: Timer?
    private let silenceInterval: TimeInterval = 1.6 // Auto-submit delay
    
    private init() {
        // Lazily initialize speech recognizer and request permissions only when needed
        // to prevent app startup crashes or freezes
    }
    
    public func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self.errorMessage = nil
                    print("[SpeechRecognizer] Speech recognition authorized")
                case .denied, .restricted:
                    self.errorMessage = "⚠️ Microphone Speech Recognition Permission Denied"
                case .notDetermined:
                    self.errorMessage = "⚠️ Speech Recognition Permission Pending"
                @unknown default:
                    self.errorMessage = "⚠️ Unknown Speech Recognition Permission Status"
                }
            }
        }
    }
    
    private func getSpeechRecognizer() -> SFSpeechRecognizer? {
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
        return speechRecognizer
    }
    
    /// Starts active listening (Advanced STT with real-time transcription and volume metering)
    public func startListening() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopListening()
            self.errorMessage = nil
            
            #if os(macOS)
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .denied || status == .restricted {
                self.errorMessage = "⚠️ Mic Permission Denied: Enable in System Settings -> Privacy -> Microphone"
                self.isListening = false
                return
            } else if status == .notDetermined {
                self.errorMessage = "⚠️ Requesting Microphone Access..."
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.startListening()
                        } else {
                            self.errorMessage = "⚠️ Microphone Access Denied by User"
                            self.isListening = false
                        }
                    }
                }
                return
            }
            #endif
            
            self.isListening = true
            self.isHotwordActive = false
            self.transcript = ""
            self.resetSilenceTimer()
            self.requestPermissions()
            
            do {
                try self.configureAudioSessionForRecording()
                try self.startAudioEngineAndRecognition(isWakeWordMode: false)
            } catch {
                print("[SpeechRecognizer] Failed to start active listening: \(error)")
                self.errorMessage = "⚠️ Voice Engine Error: \(error.localizedDescription)"
                self.stopListening()
            }
        }
    }
    
    /// Starts passive background listening (Hotword/Wake-word detection)
    public func startHotwordDetection() {
        stopListening()
        isHotwordActive = true
        if !isHotwordModeEnabled {
            isHotwordModeEnabled = true
        }
        isListening = false
        transcript = ""
        
        do {
            try configureAudioSessionForRecording()
            try startAudioEngineAndRecognition(isWakeWordMode: true)
        } catch {
            print("[SpeechRecognizer] Failed to start hotword listening: \(error)")
            errorMessage = "⚠️ Hotword Detection Notice: \(error.localizedDescription)"
            stopListening()
        }
    }
    
    /// Stops any ongoing audio engine running and terminates speech recognition tasks
    public func stopListening() {
        silenceDetectionTimer?.invalidate()
        silenceDetectionTimer = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        audioQueue.sync {
            self.recognitionRequest?.endAudio()
            self.recognitionRequest = nil
        }
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // Safely remove tap without throwing
        audioEngine.reset()
        
        isListening = false
        audioLevel = 0.0
    }
    
    private func configureAudioSessionForRecording() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }
    
    private func startAudioEngineAndRecognition(isWakeWordMode: Bool) throws {
        // SFSpeechRecognizer available check
        guard let recognizer = getSpeechRecognizer() else {
            let err = "Speech recognizer is not available on this system"
            errorMessage = "⚠️ \(err)"
            throw NSError(domain: "SpeechRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
        }
        
        let inputNode = audioEngine.inputNode
        let bus = 0
        inputNode.removeTap(onBus: bus) // Prevent crash from dual taps
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            let err = "Unable to create recognition request"
            errorMessage = "⚠️ \(err)"
            throw NSError(domain: "SpeechRecognizer", code: 2, userInfo: [NSLocalizedDescriptionKey: err])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let recordingFormat = inputNode.outputFormat(forBus: bus)
        let safeFormat = (recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0) ? recordingFormat : (AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1) ?? recordingFormat)
        
        do {
            inputNode.installTap(onBus: bus, bufferSize: 1024, format: safeFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                self.audioQueue.async {
                    if let request = self.recognitionRequest {
                        request.append(buffer)
                    }
                    self.calculateAudioLevel(buffer: buffer)
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("[SpeechRecognizer] Microphone tap notice: \(error.localizedDescription)")
            errorMessage = "⚠️ Mic Engine Notice: \(error.localizedDescription)"
        }
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                
                if isWakeWordMode {
                    self.processHotwordText(text)
                } else {
                    DispatchQueue.main.async {
                        self.transcript = text
                        if self.autoSpeechUpEnabled {
                            self.resetSilenceTimer()
                        }
                    }
                }
            }
            
            if error != nil || result?.isFinal == true {
                if !isWakeWordMode {
                    let finalVal = self.transcript
                    self.stopListening()
                    if result?.isFinal == true && self.autoSpeechUpEnabled {
                        DispatchQueue.main.async {
                            self.onSilenceDetected?(finalVal)
                        }
                    }
                } else if error != nil {
                    // Retry background hotword listening on non-fatal errors
                    self.restartHotwordDetectionDebounced()
                }
            }
        }
    }
    
    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData,
              buffer.format.channelCount > 0,
              buffer.frameLength > 0 else { return }
              
        let channelDataValue = channelData[0]
        let frameLength = UInt32(buffer.frameLength)
        
        var rms: Float = 0.0
        for i in 0..<Int(frameLength) {
            rms += channelDataValue[i] * channelDataValue[i]
        }
        rms = sqrt(rms / Float(frameLength))
        
        // Convert RMS to standard dB scale
        let level = rms > 0.0 ? 20.0 * log10(rms) : -160.0
        
        // Normalize dB value into clean 0.0...1.0 bounds for animating UI layers
        let minDb: Float = -55.0
        let maxDb: Float = -10.0
        let normalized = max(0.0, min(1.0, (level - minDb) / (maxDb - minDb)))
        
        DispatchQueue.main.async {
            self.audioLevel = normalized
        }
    }
    
    private func processHotwordText(_ text: String) {
        let lower = text.lowercased()
        // Checks for the wake keywords: "hey unison", "unison", or "computer"
        if lower.contains("unison") || lower.contains("computer") {
            DispatchQueue.main.async {
                self.stopListening()
                self.onHotwordDetected?()
            }
        }
    }
    
    private func resetSilenceTimer() {
        silenceDetectionTimer?.invalidate()
        silenceDetectionTimer = Timer.scheduledTimer(withTimeInterval: silenceInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let finalTranscript = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalTranscript.isEmpty {
                print("[SpeechRecognizer] Auto Speech-Up VAD triggered submit on silence!")
                self.stopListening()
                DispatchQueue.main.async {
                    self.onSilenceDetected?(finalTranscript)
                }
            }
        }
    }
    
    private var restartTimer: Timer?
    private func restartHotwordDetectionDebounced() {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            guard let self = self, self.isHotwordActive else { return }
            self.startHotwordDetection()
        }
    }
}
