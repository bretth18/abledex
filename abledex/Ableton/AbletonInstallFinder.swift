//
//  AbletonInstallFinder.swift
//  abledex
//

import Foundation
import AppKit

/// Locates the copies of Ableton Live installed on this machine.
nonisolated enum AbletonInstallFinder {
    /// Searched in addition to whatever LaunchServices knows about, so an
    /// install that was never registered (a fresh copy, a build kept outside
    /// /Applications) still shows up.
    private static let searchDirectories: [URL] = {
        var directories = [URL(fileURLWithPath: "/Applications")]
        if let userApps = try? FileManager.default.url(
            for: .applicationDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) {
            directories.append(userApps)
        }
        return directories
    }()

    /// Every Live install found, newest first, releases before betas.
    @concurrent
    static func findInstalls() async -> [AbletonInstall] {
        var byPath: [String: AbletonInstall] = [:]

        for url in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: AbletonInstall.bundleIdentifier) {
            add(url, to: &byPath)
        }

        let fileManager = FileManager.default
        for directory in searchDirectories {
            let contents = (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]
            )) ?? []
            for url in contents where url.pathExtension == "app"
                && url.lastPathComponent.localizedCaseInsensitiveContains("ableton live") {
                add(url, to: &byPath)
            }
        }

        return byPath.values.sorted(by: preferred)
    }

    private static func add(_ url: URL, to byPath: inout [String: AbletonInstall]) {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard byPath[resolved.path] == nil, let install = AbletonInstall(bundleURL: resolved) else { return }
        byPath[resolved.path] = install
    }

    /// Releases before betas, then newest version first. A beta usually carries
    /// the higher version number, but it is rarely the copy someone means by
    /// "open this project", so it never leads the list.
    private static func preferred(_ lhs: AbletonInstall, _ rhs: AbletonInstall) -> Bool {
        if lhs.isBeta != rhs.isBeta { return !lhs.isBeta }
        switch (lhs.version ?? "").compare(rhs.version ?? "", options: .numeric) {
        case .orderedDescending: return true
        case .orderedAscending: return false
        case .orderedSame: return lhs.bundleName < rhs.bundleName
        }
    }
}
