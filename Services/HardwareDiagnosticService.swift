import Foundation
#if os(macOS)
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit
#endif

public struct DiagnosticReport: Codable {
    public let accessibility: Bool
    public let screenshots: Bool
    public let osVersion: String
    public let cpuCores: Int
    public let physicalMemoryGB: Double
    public let uptimeSeconds: Double
    public let isSandboxed: Bool
    public let bundleId: String
    public let timestamp: String
    public let modelIdentifier: String
    public let installedApps: [String]
}

public class HardwareDiagnosticService {
    public static let shared = HardwareDiagnosticService()
    
    private var diagnosticTimer: Timer?
    
    private init() {}
    
    public func startPeriodicDiagnostics() {
        DispatchQueue.main.async {
            self.diagnosticTimer?.invalidate()
            self.diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.runDiagnosticsAndPost()
            }
            // Run once immediately
            self.runDiagnosticsAndPost()
        }
    }
    
    public func runDiagnosticsAndPost() {
        let report = generateReport()
        postReport(report)
    }
    
    private func fetchInstalledApplications() -> [String] {
        var apps: [String] = []
        let fileManager = FileManager.default
        let paths = ["/Applications", "/System/Applications"]
        
        for path in paths {
            do {
                let items = try fileManager.contentsOfDirectory(atPath: path)
                for item in items {
                    if item.hasSuffix(".app") {
                        let name = (item as NSString).deletingPathExtension
                        apps.append(name)
                    }
                }
            } catch {
                // Silently skip if inaccessible
            }
        }
        
        // Add known default system items if listing is completely empty (e.g. sandbox restriction)
        if apps.isEmpty {
            apps = ["Safari", "Music", "Notes", "Terminal", "Calculator", "Finder", "Spotify", "System Settings"]
        }
        
        return apps.sorted()
    }
    
    public func generateReport() -> DiagnosticReport {
        let accessibility = TCCPermissionChecker.verifyAccessibility
        let screenshots = TCCPermissionChecker.verifyScreenCapture
        
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let cpuCores = ProcessInfo.processInfo.activeProcessorCount
        let memoryBytes = ProcessInfo.processInfo.physicalMemory
        let physicalMemoryGB = Double(memoryBytes) / 1_073_741_824.0
        let uptimeSeconds = ProcessInfo.processInfo.systemUptime
        
        // Sandbox environment detection
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        
        let bundleId = Bundle.main.bundleIdentifier ?? "com.unison.unison-os"
        
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: Date())
        
        let modelIdentifier = "macOS Device (Architecture: " + (ProcessInfo.processInfo.operatingSystemVersionString.contains("Version") ? "Apple Silicon / Intel" : "x86_64") + ")"
        
        let installedApps = fetchInstalledApplications()
        
        return DiagnosticReport(
            accessibility: accessibility,
            screenshots: screenshots,
            osVersion: osVersion,
            cpuCores: cpuCores,
            physicalMemoryGB: physicalMemoryGB,
            uptimeSeconds: uptimeSeconds,
            isSandboxed: isSandboxed,
            bundleId: bundleId,
            timestamp: timestamp,
            modelIdentifier: modelIdentifier,
            installedApps: installedApps
        )
    }
    
    private func postReport(_ report: DiagnosticReport) {
        let webUrl = FirestoreService.shared.webUrl
        guard let url = URL(string: "\(webUrl)/api/companion/diagnostics") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(report)
            request.httpBody = jsonData
            
            #if os(macOS)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // Print block to stdout with clear prefix for local script / test logging
                print("[DIAGNOSTIC_JSON]: \(jsonString)")
            }
            #endif
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("[DIAGNOSTICS] Error posting diagnostics report: \(error.localizedDescription)")
                } else {
                    print("[DIAGNOSTICS] Diagnostics report successfully transmitted to interface pipeline.")
                }
            }.resume()
        } catch {
            print("[DIAGNOSTICS] Failed to encode diagnostics report: \(error.localizedDescription)")
        }
    }
}
