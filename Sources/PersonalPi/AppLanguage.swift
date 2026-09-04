import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let storageKey = "personalPi.appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "Follow System"
        case .english: "English"
        case .simplifiedChinese: "Simplified Chinese"
        }
    }
}

enum PersonalPiRuntimeEnvironment {
    static var isUITesting: Bool {
        let value = ProcessInfo.processInfo.environment["PERSONAL_PI_UI_TESTING"]?
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    static var piRootURL: URL {
        if let override = ProcessInfo.processInfo.environment["PERSONAL_PI_DATA_ROOT"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".pi", isDirectory: true)
    }

    static var externalProcessesDisabled: Bool {
        let value = ProcessInfo.processInfo.environment["PERSONAL_PI_DISABLE_EXTERNAL_PROCESSES"]?
            .lowercased()
        return isUITesting || value == "1" || value == "true" || value == "yes"
    }
}

enum PersonalPiPreferences {
    @MainActor
    static let store: UserDefaults = {
        guard PersonalPiRuntimeEnvironment.isUITesting else { return .standard }
        let suiteName = "dev.pi.personal.ui-testing"
        let store = UserDefaults(suiteName: suiteName) ?? .standard
        store.removePersistentDomain(forName: suiteName)
        return store
    }()
}
