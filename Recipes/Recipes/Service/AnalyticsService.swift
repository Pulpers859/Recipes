import Foundation
import OSLog

// MARK: - Analytics + Crash Tracking

final class AnalyticsService {
    static let shared = AnalyticsService()
    private init() {}
    
    private let logger = Logger(subsystem: "com.recipevault.app", category: "analytics")
    private let defaults = UserDefaults.standard
    private static let timestampFormatter = ISO8601DateFormatter()
    
    private let analyticsEnabledKey = "analytics_enabled"
    private let cleanExitKey = "app_clean_exit"
    private let lastCrashDateKey = "last_crash_detected_date"
    private let recentEventsKey = "analytics_recent_events"
    
    func configureLaunchTracking() {
        if defaults.object(forKey: cleanExitKey) != nil, defaults.bool(forKey: cleanExitKey) == false {
            defaults.set(Date().timeIntervalSince1970, forKey: lastCrashDateKey)
            track("abnormal_previous_shutdown_detected")
        }
        defaults.set(false, forKey: cleanExitKey)
    }
    
    func markCleanExit() {
        defaults.set(true, forKey: cleanExitKey)
    }
    
    func markSessionActive() {
        defaults.set(false, forKey: cleanExitKey)
    }
    
    func isAnalyticsEnabled() -> Bool {
        if defaults.object(forKey: analyticsEnabledKey) == nil {
            defaults.set(true, forKey: analyticsEnabledKey)
        }
        return defaults.bool(forKey: analyticsEnabledKey)
    }
    
    func setAnalyticsEnabled(_ enabled: Bool) {
        let previousValue = defaults.bool(forKey: analyticsEnabledKey)
        defaults.set(enabled, forKey: analyticsEnabledKey)
        if previousValue != enabled {
            track(enabled ? "analytics_enabled" : "analytics_disabled")
        }
    }
    
    func track(_ event: String, metadata: [String: String] = [:]) {
        guard isAnalyticsEnabled() else { return }
        
        let timestamp = Self.timestampFormatter.string(from: Date())
        let metadataText = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        let line = metadataText.isEmpty ? "\(timestamp) | \(event)" : "\(timestamp) | \(event) | \(metadataText)"
        
        logger.log("\(line, privacy: .public)")
        
        // Read the FULL stored history — recentEvents() returns only the last
        // 20, which silently capped the log at 21 entries instead of 200.
        var events = defaults.stringArray(forKey: recentEventsKey) ?? []
        events.append(line)
        if events.count > 200 {
            events.removeFirst(events.count - 200)
        }
        defaults.set(events, forKey: recentEventsKey)
    }
    
    func recentEvents(limit: Int = 20) -> [String] {
        let all = defaults.stringArray(forKey: recentEventsKey) ?? []
        guard all.count > limit else { return all }
        return Array(all.suffix(limit))
    }
    
    func lastAbnormalShutdownDate() -> Date? {
        guard defaults.object(forKey: lastCrashDateKey) != nil else { return nil }
        let seconds = defaults.double(forKey: lastCrashDateKey)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
