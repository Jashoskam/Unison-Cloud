import Foundation
import CoreGraphics

#if os(macOS)
import AppKit

public class EventSynthesizer {
    public static let shared = EventSynthesizer()
    
    private init() {}
    
    // Synthesizes native mouse click translating screen point via CGEvent without warping hardware cursor
    public func postCGEventMouseClick(at point: CGPoint, button: CGMouseButton = .left) -> Bool {
        // 1. Prefer Accessibility AXUIElement action to execute click without moving physical mouse
        if performAccessibilityAction(at: point) {
            return true
        }
        
        // 2. Fallback to targeted CGEvent mouse click at point without mouseMoved warping
        let source = CGEventSource(stateID: .combinedSessionState)
        let downType: CGEventType = (button == .left) ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = (button == .left) ? .leftMouseUp : .rightMouseUp
        
        guard let clickDown = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button),
              let clickUp = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button) else {
            return false
        }
        
        clickDown.post(tap: .cghidEventTap)
        usleep(40000) // 40ms down duration
        clickUp.post(tap: .cghidEventTap)
        return true
    }
    
    // Synthesizes mouse click at a screen point without moving the physical cursor
    public func postClick(at point: CGPoint, button: CGMouseButton = .left) {
        if performAccessibilityAction(at: point) {
            return
        }
        
        let source = CGEventSource(stateID: .combinedSessionState)
        let clickDown = CGEvent(mouseEventSource: source, mouseType: button == .left ? .leftMouseDown : .rightMouseDown, mouseCursorPosition: point, mouseButton: button)
        let clickUp = CGEvent(mouseEventSource: source, mouseType: button == .left ? .leftMouseUp : .rightMouseUp, mouseCursorPosition: point, mouseButton: button)
        
        clickDown?.post(tap: .cghidEventTap)
        usleep(40000) // 40ms hold down
        clickUp?.post(tap: .cghidEventTap)
    }
    
    // Synthesizes double click at a screen point
    public func postDoubleClick(at point: CGPoint) {
        postClick(at: point, button: .left)
        usleep(50000)
        let source = CGEventSource(stateID: .combinedSessionState)
        let clickDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let clickUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        clickDown?.setIntegerValueField(.mouseEventClickState, value: 2)
        clickUp?.setIntegerValueField(.mouseEventClickState, value: 2)
        clickDown?.post(tap: .cghidEventTap)
        usleep(40000)
        clickUp?.post(tap: .cghidEventTap)
    }
    
    // Synthesizes scroll event at screen point
    public func postScroll(at point: CGPoint, deltaY: Int32) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let scrollEvent = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0)
        scrollEvent?.location = point
        scrollEvent?.post(tap: .cghidEventTap)
    }
    
    // Synthesizes mouse hover (move physical cursor) at a screen point
    public func postHover(at point: CGPoint) {
        // Do NOT warp the actual physical mouse cursor on hover.
        // This prevents hijacking the user's mouse while the separate virtual green cursor moves naturally.
    }
    
    // Synthesizes keyboard event to type text
    public func postKeyboardEvent(string: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for char in string.utf16 {
            // Check for special characters like Return/Enter
            if char == 10 || char == 13 { // \n or \r
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
                continue
            }
            
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            
            var unicodeChar = char
            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
            
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
    
    // Synthesizes a key combination (e.g. "cmd+space")
    public func postKeyCombo(_ combo: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let normalized = combo.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        var flags: CGEventFlags = []
        var virtualKey: CGKeyCode = 0
        
        let parts = normalized.components(separatedBy: "+")
        for part in parts {
            switch part {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "option", "alt":
                flags.insert(.maskAlternate)
            case "control", "ctrl":
                flags.insert(.maskControl)
            case "space":
                virtualKey = 49
            case "enter", "return":
                virtualKey = 36
            case "backspace", "delete":
                virtualKey = 51
            case "escape", "esc":
                virtualKey = 53
            case "tab":
                virtualKey = 48
            case "a": virtualKey = 0
            case "s": virtualKey = 1
            case "d": virtualKey = 2
            case "f": virtualKey = 3
            case "h": virtualKey = 4
            case "g": virtualKey = 5
            case "z": virtualKey = 6
            case "x": virtualKey = 7
            case "c": virtualKey = 8
            case "v": virtualKey = 9
            case "b": virtualKey = 11
            case "q": virtualKey = 12
            case "w": virtualKey = 13
            case "e": virtualKey = 14
            case "r": virtualKey = 15
            case "y": virtualKey = 16
            case "t": virtualKey = 17
            case "o": virtualKey = 31
            case "u": virtualKey = 32
            case "i": virtualKey = 34
            case "p": virtualKey = 35
            case "l": virtualKey = 37
            case "j": virtualKey = 38
            case "k": virtualKey = 40
            case "n": virtualKey = 45
            case "m": virtualKey = 46
            default:
                break
            }
        }
        
        if virtualKey != 0 || normalized == "space" || parts.contains("space") {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
            
            keyDown?.flags = flags
            keyUp?.flags = flags
            
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
    
    // Low-level event targeting specific Process ID (PID)
    public func postClickToWindow(pid: pid_t, at relativePoint: CGPoint) {
        // Ensure virtual mouse clicks are posted to .cghidEventTap rather than targeting process ports via postToPid, preventing kernel access violation errors (0x5)
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: relativePoint, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: relativePoint, mouseButton: .left)
        
        mouseDown?.post(tap: .cghidEventTap)
        usleep(50000) // 50ms physical click hold
        mouseUp?.post(tap: .cghidEventTap)
    }
    
    // Direct global virtual event injection preventing kernel access violations (0x5)
    public func injectVirtualClick(at point: CGPoint) {
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        
        mouseDown?.post(tap: .cghidEventTap)
        usleep(50000) // 50ms physical click hold
        mouseUp?.post(tap: .cghidEventTap)
    }
    
    // Accessibility API AXUIElement click targeting
    public func performAccessibilityAction(at point: CGPoint) -> Bool {
        let systemElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemElement, Float(point.x), Float(point.y), &element)
        guard result == .success, let targetElement = element else { return false }
        
        let actionResult = AXUIElementPerformAction(targetElement, kAXPressAction as CFString)
        return actionResult == .success
    }
}
#else
// iOS Simulator Fallback
public enum CGMouseButton {
    case left, right, center
}
public class EventSynthesizer {
    public static let shared = EventSynthesizer()
    private init() {}
    
    public func postClick(at point: CGPoint, button: CGMouseButton = .left) {}
    public func postCGEventMouseClick(at point: CGPoint, button: CGMouseButton = .left) -> Bool { return false }
    public func postDoubleClick(at point: CGPoint) {}
    public func postScroll(at point: CGPoint, deltaY: Int32) {}
    public func postHover(at point: CGPoint) {}
    public func postKeyboardEvent(string: String) {}
    public func postKeyCombo(_ combo: String) {}
    public func postClickToWindow(pid: Int32, at relativePoint: CGPoint) {}
    public func injectVirtualClick(at point: CGPoint) {}
    public func performAccessibilityAction(at point: CGPoint) -> Bool { return false }
}
#endif
