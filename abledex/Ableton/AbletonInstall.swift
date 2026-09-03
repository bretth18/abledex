//
//  AbletonInstall.swift
//  abledex
//

import Foundation

/// A copy of Ableton Live installed on this machine.
///
/// Every Live build ships the same `com.ableton.live` bundle identifier, so a
/// beta and a release install are indistinguishable to LaunchServices — it picks
/// one and opens every .als with it. Installs are therefore identified by
/// bundle path, and abledex opens files with an explicit application URL.
nonisolated struct AbletonInstall: Identifiable, Hashable, Sendable {
    /// The bundle path, which is what distinguishes installs from one another.
    var id: String { url.path }

    let url: URL
    /// Bundle name, e.g. "Ableton Live 12 Suite".
    let bundleName: String
    /// Marketing version, e.g. "12.4.3" or "12.4.5b11". nil if unreadable.
    let version: String?
    /// Ableton's dated build stamp, e.g. "2026-07-07_e3d8be4d07".
    let build: String?
    let edition: Edition
    let isBeta: Bool

    enum Edition: String, Sendable {
        case suite = "Suite"
        case standard = "Standard"
        case intro = "Intro"
        case lite = "Lite"
        case trial = "Trial"
        case unknown = ""
    }

    /// "Live 12.4.3 Suite", or the bundle name when no version could be read.
    var displayName: String {
        guard let version else { return bundleName }
        let edition = edition == .unknown ? "" : " \(edition.rawValue)"
        return "Live \(version)\(edition)"
    }

    /// Major.minor of the install, for comparison against a project's saved
    /// version. nil when the version string has no numeric prefix.
    var majorMinor: String? {
        Self.majorMinor(of: version)
    }

    /// Major.minor of any Live version string, ignoring patch and beta suffixes.
    /// "12.4.5b11" -> "12.4", "11.3" -> "11.3", "12" -> nil.
    static func majorMinor(of version: String?) -> String? {
        guard let version else { return nil }
        let parts = version.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let major = parts[0].prefix { $0.isNumber }
        let minor = parts[1].prefix { $0.isNumber }
        guard !major.isEmpty, !minor.isEmpty else { return nil }
        return "\(major).\(minor)"
    }

    /// Whether this install is at least as new as the version a project was
    /// saved with. Live refuses to open sets from a newer major/minor release.
    func canOpenProject(savedWith projectVersion: String?) -> Bool {
        guard let projectVersion, let mine = majorMinor, let theirs = Self.majorMinor(of: projectVersion) else {
            return true
        }
        return compare(mine, theirs) != .orderedAscending
    }

    private func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }
}

nonisolated extension AbletonInstall {
    /// Reads an install's metadata from its bundle, or nil if it isn't Live.
    init?(bundleURL: URL) {
        guard let bundle = Bundle(url: bundleURL),
              bundle.bundleIdentifier == AbletonInstall.bundleIdentifier else { return nil }

        let info = bundle.infoDictionary ?? [:]
        let name = bundleURL.deletingPathExtension().lastPathComponent
        // Live's version string is "12.4.3 (2026-07-07_e3d8be4d07)".
        let raw = info["CFBundleShortVersionString"] as? String
        let version = raw?.split(separator: " ").first.map(String.init)
        let build = raw?
            .drop { $0 != "(" }
            .trimmingCharacters(in: CharacterSet(charactersIn: "()"))

        self.url = bundleURL
        self.bundleName = name
        self.version = version
        self.build = build?.isEmpty == true ? nil : build
        self.edition = Edition.allNames.first { name.localizedCaseInsensitiveContains($0.rawValue) } ?? .unknown
        // Betas ship as "Ableton Live 12 Beta.app" with a "b<n>" version suffix.
        self.isBeta = name.localizedCaseInsensitiveContains("beta")
            || (version.map { $0.contains(where: \.isLetter) } ?? false)
    }

    static let bundleIdentifier = "com.ableton.live"
}

private nonisolated extension AbletonInstall.Edition {
    static let allNames: [Self] = [.suite, .standard, .intro, .lite, .trial]
}
