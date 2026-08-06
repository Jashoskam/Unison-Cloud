import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public struct CoordinateMapper {
    // Translates Gemini normalized point [0, 1000] to actual screen coordinate
    public static func translateNormalizedToScreen(normalizedX: Double, normalizedY: Double) -> CGPoint {
        #if os(macOS)
        guard let mainScreen = NSScreen.screens.first else { return .zero }
        let screenFrame = mainScreen.frame
        
        let screenWidth = screenFrame.size.width
        let screenHeight = screenFrame.size.height
        let screenOffsetX = screenFrame.origin.x
        let screenOffsetY = screenFrame.origin.y
        
        // Formulate physical X & Y with screen offsets without inverting Y
        let physicalX = screenOffsetX + (normalizedX / 1000.0 * screenWidth)
        let physicalY = screenOffsetY + (normalizedY / 1000.0 * screenHeight)
        
        return CGPoint(x: physicalX, y: physicalY)
        #else
        let screenFrame = UIScreen.main.bounds
        let screenWidth = screenFrame.size.width
        let screenHeight = screenFrame.size.height
        
        let physicalX = (normalizedX / 1000.0 * screenWidth)
        let physicalY = (normalizedY / 1000.0 * screenHeight)
        return CGPoint(x: physicalX, y: physicalY)
        #endif
    }
    
    // Translates screen coordinate to Gemini normalized space [0, 1000]
    public static func translateScreenToNormalized(physicalPoint: CGPoint) -> (Double, Double) {
        #if os(macOS)
        guard let mainScreen = NSScreen.screens.first else { return (500, 500) }
        let screenFrame = mainScreen.frame
        
        let screenWidth = screenFrame.size.width
        let screenHeight = screenFrame.size.height
        let screenOffsetX = screenFrame.origin.x
        let screenOffsetY = screenFrame.origin.y
        
        let normalizedX = ((physicalPoint.x - screenOffsetX) / screenWidth) * 1000.0
        let normalizedY = ((physicalPoint.y - screenOffsetY) / screenHeight) * 1000.0
        
        return (
            max(0, min(1000, normalizedX)),
            max(0, min(1000, normalizedY))
        )
        #else
        let screenFrame = UIScreen.main.bounds
        let screenWidth = screenFrame.size.width
        let screenHeight = screenFrame.size.height
        
        let normalizedX = (physicalPoint.x / screenWidth) * 1000.0
        let normalizedY = (physicalPoint.y / screenHeight) * 1000.0
        return (
            max(0, min(1000, normalizedX)),
            max(0, min(1000, normalizedY))
        )
        #endif
    }
}
