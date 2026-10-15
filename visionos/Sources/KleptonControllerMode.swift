import Foundation

/// Shared wire values with AVPPlayCore.ControllerMode. Local choices survive app updates.
enum KleptonControllerMode: String, CaseIterable {
    case standard, surreal
    static let preferenceKey = "klepton.controllerMode"
    static func selected(defaults: UserDefaults = .standard,
                         bundleDefault: String? = Bundle.main.object(forInfoDictionaryKey: "KLControllerModeDefault") as? String) -> Self {
        if let local = defaults.string(forKey: preferenceKey), let mode = Self(rawValue: local) { return mode }
        return bundleDefault.flatMap(Self.init(rawValue:)) ?? .standard
    }
    func save(defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
}
