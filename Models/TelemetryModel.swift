import Foundation

/// State representation of a physical GPIO Pin on properties of Companion Node
public struct GPIOPinState: Codable, Hashable {
    public var state: Int // 0 or 1
    public var pin: Int
    public var alias: String
    
    public init(state: Int, pin: Int, alias: String) {
        self.state = state
        self.pin = pin
        self.alias = alias
    }
}

/// System telemetry data model received from real-time Supabase/Cloud synchronization
public struct SystemTelemetry: Codable, Hashable {
    public var cpuTemp: Double
    public var relay1Active: Bool
    public var relay2Active: Bool
    public var faultLedActive: Bool
    public var lastUpdated: Date?
    
    public init(cpuTemp: Double = 42.0, relay1Active: Bool = false, relay2Active: Bool = false, faultLedActive: Bool = false, lastUpdated: Date? = nil) {
        self.cpuTemp = cpuTemp
        self.relay1Active = relay1Active
        self.relay2Active = relay2Active
        self.faultLedActive = faultLedActive
        self.lastUpdated = lastUpdated
    }
}

/// Singular item in the secure cognitive AI memory index
public struct MemoryItem: Identifiable, Codable, Hashable {
    public var id = UUID()
    public var category: String // Preference, Constraint, Project, Attribute
    public var content: String
    public var createdAt: Date
    
    public init(category: String, content: String, createdAt: Date = Date()) {
        self.category = category
        self.content = content
        self.createdAt = createdAt
    }
}

/// Spotify Cast Track playlist queues
public struct Song: Identifiable, Codable, Hashable {
    public var id: String
    public var title: String
    public var artist: String
    public var duration: String
    
    public init(id: String, title: String, artist: String, duration: String) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

/// Syslog notifications and alerts logs
public struct SysLogItem: Identifiable, Codable, Hashable {
    public var id = UUID()
    public var tag: String
    public var message: String
    public var timestamp: String
    public var isError: Bool
    
    public init(tag: String, message: String, timestamp: String, isError: Bool = false) {
        self.tag = tag
        self.message = message
        self.timestamp = timestamp
        self.isError = isError
    }
}
