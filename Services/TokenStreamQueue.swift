import Foundation
import SwiftUI
import Combine

/// TokenStreamQueue provides a 60fps smooth packet stream animation buffer for real-time AI responses,
/// eliminating text chunk jumping and rendering word-by-word typewriter packets with live reasoning disclosure.
@MainActor
public final class TokenStreamQueue: ObservableObject {
    public static let shared = TokenStreamQueue()
    
    @Published public var displayedText: String = ""
    @Published public var thinkingText: String = ""
    @Published public var isThinking: Bool = false
    @Published public var isStreamingActive: Bool = false
    @Published public var thinkingDurationSeconds: Double = 0.0
    
    private var tokenQueue: [String] = []
    private var thinkingQueue: [String] = []
    private var timer: AnyCancellable?
    private var thinkingStartTime: Date?
    
    private init() {}
    
    /// Reset the queue for a new incoming AI response turn
    public func reset() {
        tokenQueue.removeAll()
        thinkingQueue.removeAll()
        displayedText = ""
        thinkingText = ""
        isThinking = false
        isStreamingActive = false
        thinkingDurationSeconds = 0.0
        thinkingStartTime = nil
        timer?.cancel()
        timer = nil
    }
    
    /// Push incoming reasoning / thinking tokens into the queue
    public func pushThinkingChunk(_ chunk: String) {
        if thinkingStartTime == nil {
            thinkingStartTime = Date()
            isThinking = true
        }
        
        let words = chunk.components(separatedBy: " ")
        for (idx, w) in words.enumerated() {
            let token = idx == words.count - 1 ? w : w + " "
            thinkingQueue.append(token)
        }
        
        startTimerIfNeeded()
    }
    
    /// Push incoming text delta chunk into the queue
    public func pushTextChunk(_ chunk: String) {
        if isThinking {
            isThinking = false
            if let start = thinkingStartTime {
                thinkingDurationSeconds = Date().timeIntervalSince(start)
            }
        }
        isStreamingActive = true
        
        let words = chunk.components(separatedBy: " ")
        for (idx, w) in words.enumerated() {
            let token = idx == words.count - 1 ? w : w + " "
            tokenQueue.append(token)
        }
        
        startTimerIfNeeded()
    }
    
    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        
        timer = Timer.publish(every: 0.025, on: .main, in: .common) // ~40 words per second pacing
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.processNextPacket()
            }
    }
    
    private func processNextPacket() {
        // First drain thinking queue if active
        if !thinkingQueue.isEmpty {
            let countToDrain = min(thinkingQueue.count, 2)
            let packet = thinkingQueue.prefix(countToDrain).joined()
            thinkingQueue.removeFirst(countToDrain)
            thinkingText += packet
            if let start = thinkingStartTime {
                thinkingDurationSeconds = Date().timeIntervalSince(start)
            }
            return
        }
        
        // Drain main token queue word-by-word
        if !tokenQueue.isEmpty {
            let countToDrain = min(tokenQueue.count, 2)
            let packet = tokenQueue.prefix(countToDrain).joined()
            tokenQueue.removeFirst(countToDrain)
            displayedText += packet
            return
        }
        
        // If queues are empty and non-active, stop timer
        if tokenQueue.isEmpty && thinkingQueue.isEmpty {
            timer?.cancel()
            timer = nil
        }
    }
    
    /// Instantly flush all remaining tokens to complete the stream immediately
    public func flushAll() {
        if !thinkingQueue.isEmpty {
            thinkingText += thinkingQueue.joined()
            thinkingQueue.removeAll()
        }
        if !tokenQueue.isEmpty {
            displayedText += tokenQueue.joined()
            tokenQueue.removeAll()
        }
        timer?.cancel()
        timer = nil
        isStreamingActive = false
        isThinking = false
    }
}
