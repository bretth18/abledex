//
//  UpdateService.swift
//  abledex
//
//  Created by Brett Henderson on 12/20/25.
//

import Foundation
import AppKit

@MainActor
@Observable
final class UpdateService {
    static let shared = UpdateService()

    private let repoOwner = "bretth18"
    private let repoName = "abledex"

    var isChecking: Bool = false
    var updateAvailable: Bool = false
    var latestVersion: String?
    var latestReleaseURL: URL?
    var latestPkgURL: URL?
    var releaseNotes: String?
    var lastCheckDate: Date?
    var errorMessage: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private init() {}

    struct GitHubRelease: Codable {
        let tagName: String
        let name: String
        let body: String?
        let htmlUrl: String
        let assets: [GitHubAsset]
        let prerelease: Bool
        let draft: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlUrl = "html_url"
            case assets
            case prerelease
            case draft
        }
    }

    struct GitHubAsset: Codable {
        let name: String
        let browserDownloadUrl: String
        let size: Int
        let contentType: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
            case size
            case contentType = "content_type"
        }
    }

    func checkForUpdates() async {
        guard !isChecking else { return }

        isChecking = true
        errorMessage = nil

        defer {
            isChecking = false
            lastCheckDate = Date()
        }

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Abledex/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                return
            }

            if httpResponse.statusCode == 404 {
                // No releases yet
                updateAvailable = false
                latestVersion = nil
                return
            }

            guard httpResponse.statusCode == 200 else {
                errorMessage = "GitHub API error: \(httpResponse.statusCode)"
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            // Skip drafts and prereleases
            if release.draft || release.prerelease {
                updateAvailable = false
                return
            }

            // Parse version from tag (remove 'v' prefix if present)
            let versionString = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            latestVersion = versionString
            releaseNotes = release.body
            latestReleaseURL = URL(string: release.htmlUrl)

            // Find .pkg asset
            if let pkgAsset = release.assets.first(where: { $0.name.hasSuffix(".pkg") }) {
                latestPkgURL = URL(string: pkgAsset.browserDownloadUrl)
            }

            // Compare versions
            updateAvailable = isNewerVersion(versionString, than: currentVersion)

        } catch {
            errorMessage = "Failed to check for updates: \(error.localizedDescription)"
        }
    }

    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newComponents = new.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(newComponents.count, currentComponents.count)

        for i in 0..<maxLength {
            let newPart = i < newComponents.count ? newComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0

            if newPart > currentPart {
                return true
            } else if newPart < currentPart {
                return false
            }
        }

        return false
    }

    func downloadAndInstallUpdate() {
        guard let pkgURL = latestPkgURL else {
            // Fall back to release page
            if let releaseURL = latestReleaseURL {
                NSWorkspace.shared.open(releaseURL)
            }
            return
        }

        // Open the .pkg URL in browser to download
        NSWorkspace.shared.open(pkgURL)
    }

    func openReleasePage() {
        if let releaseURL = latestReleaseURL {
            NSWorkspace.shared.open(releaseURL)
        } else {
            let url = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!
            NSWorkspace.shared.open(url)
        }
    }
}
