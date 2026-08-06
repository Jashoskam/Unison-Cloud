import Foundation
#if os(macOS)
import ScreenCaptureKit
#endif
import CoreMedia
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
public class ScreenCaptureManager: NSObject, SCStreamOutput {
    public static let shared = ScreenCaptureManager()
    
    private var stream: SCStream?
    private var lastCapturedFrame: CGImage?
    private var lastValidFrameData: Data?
    private let frameQueue = DispatchQueue(label: "com.unison.screencapture.queue")
    private var isCapturing = false
    
    public override init() {
        super.init()
        startPersistentCapture()
    }
    
    private func verifyActualScreenCapturePermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return false
    }

    private func createDummyBlackImage() -> Data? {
        let width = 100
        let height = 100
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage() else { return nil }
        return compressImage(cgImage, maxDimension: 100, compressionQuality: 0.5)
    }

    public func startPersistentCapture() {
        guard verifyActualScreenCapturePermission() else {
            print("[ScreenCaptureManager] Skipping SCStream: Real OS ScreenCapture permission not granted.")
            return
        }
        guard !isCapturing else { return }
        SCShareableContent.getWithCompletionHandler { [weak self] content, error in
            guard let self = self else { return }
            guard error == nil, let content = content, let display = content.displays.first else { return }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = 1024
            config.height = 1024
            config.queueDepth = 5
            config.pixelFormat = kCVPixelFormatType_32BGRA
            
            do {
                let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
                try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.frameQueue)
                self.stream = newStream
                
                newStream.startCapture { [weak self] error in
                    if let error = error {
                        print("Failed to start persistent capture: \(error)")
                    } else {
                        self?.isCapturing = true
                        print("SCStream persistent background capture started.")
                    }
                }
            } catch {
                print("SCStream error: \(error)")
            }
        }
    }
    
    public func stopPersistentCapture() {
        stream?.stopCapture { [weak self] _ in
            self?.isCapturing = false
            self?.stream = nil
        }
    }
    
    // Captures the main display instantly using persistent background SCStream
    public func captureCurrentScreen(completion: @escaping (Data?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            
            guard self.verifyActualScreenCapturePermission() else {
                print("[ScreenCaptureManager] No real OS permission. Returning mock screen image to avoid OS prompt.")
                let dummyImage = self.createDummyBlackImage()
                completion(dummyImage)
                return
            }
            
            self.startPersistentCapture()
            
            if let frame = self.lastCapturedFrame,
               let compressedData = self.compressImage(frame, maxDimension: 1024, compressionQuality: 0.75) {
                self.lastValidFrameData = compressedData
                completion(compressedData)
                return
            }
            
            let maxRetries = 3
            
            func attemptCapture(currentRetry: Int) {
                var attempts = 0
                func pollFrame() {
                    if let frame = self.lastCapturedFrame,
                       let compressedData = self.compressImage(frame, maxDimension: 1024, compressionQuality: 0.75) {
                        self.lastValidFrameData = compressedData
                        completion(compressedData)
                        return
                    } else if attempts < 10 {
                        attempts += 1
                        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
                            pollFrame()
                        }
                    } else {
                        print("[ScreenCaptureManager] SCStream frame poll failed. Trying screencapture CLI (Retry \(currentRetry + 1)/\(maxRetries)).")
                        if let cliData = self.captureScreenViaCLI() {
                            self.lastValidFrameData = cliData
                            completion(cliData)
                            return
                        }
                        
                        if currentRetry < maxRetries {
                            let nextRetry = currentRetry + 1
                            print("[ScreenCaptureManager] Capture failed. Retrying in 1.5 seconds...")
                            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.5) {
                                attemptCapture(currentRetry: nextRetry)
                            }
                        } else {
                            if let cached = self.lastValidFrameData {
                                print("[ScreenCaptureManager] Max retries reached. Falling back to last valid in-memory cached frame.")
                                completion(cached)
                            } else {
                                print("[ScreenCaptureManager] Terminal capture failure. Falling back to dummy black image to prevent loop lockout.")
                                let dummy = self.createDummyBlackImage()
                                completion(dummy)
                            }
                        }
                    }
                }
                pollFrame()
            }
            
            attemptCapture(currentRetry: 0)
        }
    }
    
    private func captureScreenViaCLI() -> Data? {
        guard verifyActualScreenCapturePermission() else {
            print("[ScreenCaptureManager] Skipping CLI screencapture: Real OS ScreenCapture permission not granted.")
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        
        let workspaceDir = NSHomeDirectory()
        let tempFileURL = URL(fileURLWithPath: workspaceDir).appendingPathComponent("unison_screencapture.png")
        
        try? FileManager.default.removeItem(at: tempFileURL)
        process.arguments = ["-x", "-t", "png", tempFileURL.path]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                if let imgData = try? Data(contentsOf: tempFileURL) {
                    try? FileManager.default.removeItem(at: tempFileURL)
                    if let image = NSImage(data: imgData),
                       let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        return self.compressImage(cgImage, maxDimension: 1024, compressionQuality: 0.75)
                    }
                    return imgData
                }
            }
        } catch {
            print("[ScreenCaptureManager] CLI screencapture failed: \(error)")
        }
        return nil
    }
    
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Convert image buffer to CGImage
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            self.lastCapturedFrame = cgImage
        }
    }
    
    private func compressImage(_ image: CGImage, maxDimension: CGFloat, compressionQuality: CGFloat) -> Data? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        var newWidth = width
        var newHeight = height
        
        if width > maxDimension || height > maxDimension {
            if width > height {
                newWidth = maxDimension
                newHeight = (height / width) * maxDimension
            } else {
                newHeight = maxDimension
                newWidth = (width / height) * maxDimension
            }
        }
        
        let size = CGSize(width: newWidth, height: newHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: Int(newWidth), height: Int(newHeight), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard let resizedImage = context.makeImage() else { return nil }
        
        let mutableData = NSMutableData()
        let typeIdentifier = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, typeIdentifier, 1, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        
        CGImageDestinationAddImage(destination, resizedImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        
        return mutableData as Data
    }
}
#else
// iOS Simulator Fallback
public class ScreenCaptureManager: NSObject {
    public static let shared = ScreenCaptureManager()
    private override init() {
        super.init()
    }
    
    public func startPersistentCapture() {}
    public func stopPersistentCapture() {}
    public func captureCurrentScreen(completion: @escaping (Data?) -> Void) {
        let width = 100
        let height = 100
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            completion(nil)
            return
        }
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let mutableData = NSMutableData()
        if let cgImage = context.makeImage(),
           let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) {
            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.5]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            if CGImageDestinationFinalize(destination) {
                completion(mutableData as Data)
                return
            }
        }
        completion(nil)
    }
}
#endif
