//
//  AbletonPreference.swift
//  abledex
//

import Foundation

/// Which Live install opens a project, when more than one is installed.
nonisolated enum AbletonPreference {
    /// Bundle path of the install to always use, or nil to ask each time.
    private static let defaultsKey = "defaultAbletonBundlePath"

    static var alwaysOpenWithPath: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
    }

    /// The remembered install, if it is still present on disk. A remembered
    /// install that has been deleted or renamed falls back to asking again
    /// rather than silently opening the wrong Live.
    static func rememberedInstall(among installs: [AbletonInstall]) -> AbletonInstall? {
        guard let path = alwaysOpenWithPath else { return nil }
        return installs.first { $0.id == path }
    }

    static func remember(_ install: AbletonInstall) {
        alwaysOpenWithPath = install.id
    }

    static func clear() {
        alwaysOpenWithPath = nil
    }
}
