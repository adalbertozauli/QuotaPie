import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppPreferences {
    private let defaults: UserDefaults
    var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: "refreshMinutes") } }
    var hover: Bool { didSet { defaults.set(hover, forKey: "hover"); if !hover && !click { click = true } } }
    var click: Bool { didSet { defaults.set(click, forKey: "click"); if !click && !hover { hover = true } } }
    var absoluteTime: Bool { didSet { defaults.set(absoluteTime, forKey: "absoluteTime") } }
    var countdown: Bool { didSet { defaults.set(countdown, forKey: "countdown") } }
    var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "retentionDays") } }
    var codexPath: String { didSet { defaults.set(codexPath, forKey: "codexPath") } }
    var claudeInteractive: Bool { didSet { defaults.set(claudeInteractive, forKey: "claudeInteractive") } }
    var disabledProviders: [String] { didSet { defaults.set(disabledProviders, forKey: "disabledProviders") } }
    var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: "onboardingComplete") } }
    var alerts: Bool { didSet { defaults.set(alerts, forKey: "alerts") } }
    var renewalAlerts: Bool { didSet { defaults.set(renewalAlerts, forKey: "renewalAlerts") } }
    #if DEBUG
    var demonstration = false
    #endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["refreshMinutes": 2, "hover": true, "click": true, "absoluteTime": true,
                                     "countdown": true, "appearance": "system", "retentionDays": 30])
        refreshMinutes = defaults.integer(forKey: "refreshMinutes")
        hover = defaults.bool(forKey: "hover")
        click = defaults.bool(forKey: "click")
        absoluteTime = defaults.bool(forKey: "absoluteTime")
        countdown = defaults.bool(forKey: "countdown")
        appearance = defaults.string(forKey: "appearance") ?? "system"
        retentionDays = defaults.integer(forKey: "retentionDays")
        codexPath = defaults.string(forKey: "codexPath") ?? ""
        claudeInteractive = defaults.bool(forKey: "claudeInteractive")
        disabledProviders = defaults.stringArray(forKey: "disabledProviders") ?? []
        onboardingComplete = defaults.bool(forKey: "onboardingComplete")
        alerts = defaults.bool(forKey: "alerts")
        renewalAlerts = defaults.bool(forKey: "renewalAlerts")
    }
    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    func enabled(_ id: ProviderIdentity) -> Bool { !disabledProviders.contains(id.rawValue) }
    func setEnabled(_ id: ProviderIdentity, _ enabled: Bool) {
        disabledProviders.removeAll { $0 == id.rawValue }
        if !enabled { disabledProviders.append(id.rawValue) }
    }
}

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()
    let preferences: AppPreferences = {
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing") {
            let defaults = UserDefaults(suiteName: "AIUsageMonitor.UITesting") ?? .standard
            defaults.removePersistentDomain(forName: "AIUsageMonitor.UITesting")
            let preferences = AppPreferences(defaults: defaults)
            preferences.onboardingComplete = true
            preferences.demonstration = true
            preferences.appearance = CommandLine.arguments.contains("--ui-dark") ? "dark" : "light"
            return preferences
        }
        #endif
        return AppPreferences()
    }()
    lazy var coordinator = UsageRefreshCoordinator(preferences: preferences, persistHistory: !CommandLine.arguments.contains("--ui-testing"))
}
