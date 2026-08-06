import Foundation

#if os(macOS)
public class LocalShellExecutor {
    public static let shared = LocalShellExecutor()
    private init() {}
    
    public func execute(command: String, in directory: String, completion: @escaping (Int32, String) -> Void) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            
            // Watchdog timer to kill hanging or infinite loops
            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30.0, execute: timeoutWorkItem)
            
            process.waitUntilExit()
            timeoutWorkItem.cancel()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let combinedOutput = String(data: outputData, encoding: .utf8)?
                .appending(String(data: errorData, encoding: .utf8) ?? "") ?? ""
            
            completion(process.terminationStatus, combinedOutput)
        } catch {
            completion(-1, "Failed to start shell process: \(error.localizedDescription)")
        }
    }
}
#else
public class LocalShellExecutor {
    public static let shared = LocalShellExecutor()
    private init() {}
    
    public func execute(command: String, in directory: String, completion: @escaping (Int32, String) -> Void) {
        completion(0, "Shell execution bypassed on non-macOS hardware.")
    }
}
#endif
