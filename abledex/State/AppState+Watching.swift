//
//  AppState+Watching.swift
//  abledex
//

import Foundation
import CoreServices
import AppKit
import os

extension AppState {
    // MARK: - File System Watching (FSEvents)

    static let watchLog = Logger(subsystem: "computerdata.abledex", category: "filewatch")

    /// Traces watcher decisions to the unified log; DEBUG builds also append
    /// to $TMPDIR/abledex-watch.log so scan/replay behavior can be inspected
    /// without a console attached.
    private static func watchTrace(_ message: String) {
        watchLog.log("\(message, privacy: .public)")
        #if DEBUG
        let line = "\(Date()) \(message)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("abledex-watch.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        #endif
    }

    /// A volume with enabled locations on it, resolved to what FSEvents needs.
    struct VolumeWatchTarget {
        let key: String        // persistence key: "boot" or volume UUID
        let isBoot: Bool
        let device: dev_t
        let volumeRoot: String
        var paths: [String]    // absolute location paths on this volume
    }

    func volumeWatchTargets() -> [VolumeWatchTarget] {
        var targets: [String: VolumeWatchTarget] = [:]
        for location in locations where location.isEnabled {
            guard FileManager.default.fileExists(atPath: location.path) else { continue }
            let url = URL(fileURLWithPath: location.path)
            guard let values = try? url.resourceValues(forKeys: [.volumeURLKey, .volumeUUIDStringKey]),
                  let volumeRoot = values.volume?.path else { continue }
            var status = stat()
            guard stat(location.path, &status) == 0 else { continue }

            let isBoot = volumeRoot == "/"
            let key = isBoot ? "boot" : (values.volumeUUIDString ?? volumeRoot)
            targets[key, default: VolumeWatchTarget(
                key: key, isBoot: isBoot, device: status.st_dev, volumeRoot: volumeRoot, paths: []
            )].paths.append(location.path)
        }
        return targets.values.map { target in
            var sorted = target
            sorted.paths.sort()
            return sorted
        }
    }

    // MARK: Baseline persistence (per volume)

    func baselineDefaultsKey(_ volumeKey: String) -> String { "fsEventsBaseline.\(volumeKey)" }
    private func journalDefaultsKey(_ volumeKey: String) -> String { "fsEventsJournal.\(volumeKey)" }

    /// The stored replay baseline, or nil when replay can't be trusted.
    /// Device event IDs only mean something within the journal that issued
    /// them, so external volumes also require a matching journal UUID.
    func storedBaseline(for target: VolumeWatchTarget) -> FSEventStreamEventId? {
        let defaults = UserDefaults.standard
        var stored = defaults.string(forKey: baselineDefaultsKey(target.key)).flatMap { UInt64($0) }
        if stored == nil, target.isBoot {
            // Pre-per-volume releases kept a single host-wide key
            stored = defaults.string(forKey: "fsEventsLastEventID").flatMap { UInt64($0) }
        }
        guard let stored else { return nil }
        if !target.isBoot {
            guard let journal = FileSystemWatcher.journalUUID(forDevice: target.device),
                  journal == defaults.string(forKey: journalDefaultsKey(target.key)) else { return nil }
        }
        return stored
    }

    func persistBaseline(_ id: FSEventStreamEventId, for target: VolumeWatchTarget) {
        let defaults = UserDefaults.standard
        defaults.set(String(id), forKey: baselineDefaultsKey(target.key))
        if !target.isBoot, let journal = FileSystemWatcher.journalUUID(forDevice: target.device) {
            defaults.set(journal, forKey: journalDefaultsKey(target.key))
        }
    }

    /// A fresh "consistent as of now" baseline in the volume's own ID space.
    /// nil when the device's journal isn't available (yet). A zero ID must
    /// never be persisted or used as sinceWhen, or the stream replays the
    /// volume's entire history.
    func currentBaseline(for target: VolumeWatchTarget) -> FSEventStreamEventId? {
        if target.isBoot { return FSEventsGetCurrentEventId() }
        let id = FileSystemWatcher.lastEventID(forDevice: target.device)
        return id > 0 ? id : nil
    }

    /// FSEvents' device APIs (journal UUID, last event ID) become available
    /// shortly AFTER the mount notification fires. Poll briefly so replay
    /// validation doesn't misread "not ready yet" as "no journal".
    private func waitForJournal(device: dev_t, timeout: Duration = .seconds(3)) async -> String? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let uuid = FileSystemWatcher.journalUUID(forDevice: device) { return uuid }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return FileSystemWatcher.journalUUID(forDevice: device)
    }

    // MARK: Watcher lifecycle

    /// Launch-time indexing: locations covered by a valid journal baseline
    /// replay deltas; only the remainder gets a real scan.
    func startAutomaticIndexing() async {
        let autoScan = UserDefaults.standard.object(forKey: "autoScanOnLaunch") as? Bool ?? true
        let targets = volumeWatchTargets()

        var volumeKeyByPath: [String: String] = [:]
        for target in targets {
            for path in target.paths { volumeKeyByPath[path] = target.key }
        }
        let replayableKeys = Set(targets.filter { storedBaseline(for: $0) != nil }.map(\.key))

        let needingScan = locations.filter { location in
            guard location.isEnabled, let key = volumeKeyByPath[location.path] else { return false }
            return location.lastScannedAt == nil || !replayableKeys.contains(key)
        }

        if needingScan.isEmpty || !autoScan {
            ensureFileWatchers()
        } else {
            await runScan(coveringLocations: needingScan) { scanner, progress in
                try await scanner.scanLocations(needingScan, forceReparse: false, progress: progress)
            }
        }
    }

    /// (Re)starts one stream per volume, resuming from the stored baseline
    /// when valid (replays history), else watching from now. No-op for volumes
    /// already watched correctly; streams for vanished volumes stop.
    func ensureFileWatchers() {
        let targets = volumeWatchTargets()
        let activeKeys = Set(targets.map(\.key))

        for (key, watcher) in fileWatchers where !activeKeys.contains(key) {
            watcher.stop()
            fileWatchers[key] = nil
        }

        for target in targets {
            if let existing = fileWatchers[target.key], existing.absolutePaths == target.paths { continue }
            fileWatchers[target.key]?.stop()

            let sinceID = storedBaseline(for: target)
                ?? currentBaseline(for: target)
                ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
            let streamTarget: FileSystemWatcher.Target = target.isBoot
                ? .host(paths: target.paths)
                : .device(
                    device: target.device,
                    volumeRoot: target.volumeRoot,
                    relativePaths: target.paths.map { Self.relativePath($0, toVolumeRoot: target.volumeRoot) }
                )

            let volumeKey = target.key
            let watcher = FileSystemWatcher(target: streamTarget, sinceEventID: sinceID) { [weak self] events, latestEventID in
                Task { @MainActor [weak self] in
                    self?.enqueueFileEvents(events, latestEventID: latestEventID, volumeKey: volumeKey)
                }
            }
            fileWatchers[target.key] = watcher
            watcher.start()
        }
    }

    private static func relativePath(_ path: String, toVolumeRoot root: String) -> String {
        guard path != root else { return "" }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    private func enqueueFileEvents(
        _ events: [FileSystemWatcher.Event],
        latestEventID: FSEventStreamEventId,
        volumeKey: String
    ) {
        pendingFileEvents.append(contentsOf: events)
        latestEventIDsByVolume[volumeKey] = latestEventID
        guard fileEventsDrainTask == nil else { return }
        fileEventsDrainTask = Task { @MainActor in
            // Extra coalescing: Live touches several files per save
            try? await Task.sleep(for: .milliseconds(500))
            while !pendingFileEvents.isEmpty {
                let batch = pendingFileEvents
                pendingFileEvents.removeAll()
                await processFileEvents(batch)
            }
            fileEventsDrainTask = nil
            // The index has caught up with each volume as of its last event.
            // Never move a baseline backward: replayed (historical) events
            // carry IDs older than a baseline a scan persisted mid-drain, and
            // regressing would re-deliver the same events on every remount.
            let caughtUp = latestEventIDsByVolume
            latestEventIDsByVolume.removeAll()
            let defaults = UserDefaults.standard
            for (key, id) in caughtUp {
                let stored = defaults.string(forKey: baselineDefaultsKey(key)).flatMap { UInt64($0) } ?? 0
                if id > stored {
                    defaults.set(String(id), forKey: baselineDefaultsKey(key))
                }
            }
        }
    }

    /// Changed .als files re-parse individually; removed ones drop their
    /// record; directory-level changes and journal gaps trigger an incremental
    /// scan of the affected locations (whose pruning handles folder removals).
    private func processFileEvents(_ events: [FileSystemWatcher.Event]) async {
        var locationIDsToScan = Set<UUID>()
        var alsToRescan: [String] = []
        var alsToDelete: [String] = []
        var seenPaths = Set<String>()

        func markContainingLocations(of path: String) {
            for location in locations where location.isEnabled {
                if path == location.path || path.hasPrefix(location.path + "/") {
                    locationIDsToScan.insert(location.id)
                }
            }
        }

        for event in events {
            let path = event.path
            guard seenPaths.insert(path).inserted else { continue }
            Self.watchTrace("event \(String(format: "0x%08x", event.flags)) \(path)")

            // Volume lifecycle is VolumeMonitor's job; hidden-path churn
            // (.fseventsd, .Spotlight-V100, .Trashes, .DS_Store) accompanies
            // every mount and is invisible to the crawler anyway.
            if event.isMountOrUnmount || path.contains("/.") {
                continue
            }
            if event.mustScanSubDirs {
                markContainingLocations(of: path)
                continue
            }
            // Live's own churn on every save; never affects the index
            if path.contains("/Backup/") || path.contains("/Trash/") || path.contains("/Ableton Project Info/") {
                continue
            }
            if path.lowercased().hasSuffix(".als") {
                if FileManager.default.fileExists(atPath: path) {
                    alsToRescan.append(path)
                } else {
                    alsToDelete.append(path)
                }
            } else if event.isDirectory, event.wasCreated || event.wasRemoved || event.wasRenamed {
                // Folder moves deliver no per-file events; only a scan can
                // discover (or prune) the projects inside
                markContainingLocations(of: path)
            }
        }

        for path in alsToDelete {
            try? await database.deleteProject(byAlsFilePath: path)
        }
        let scanner = self.scanner
        for path in alsToRescan {
            _ = try? await scanner.scanSingleProject(alsFilePath: path)
        }
        if !locationIDsToScan.isEmpty, !isScanning {
            let affected = locations.filter { locationIDsToScan.contains($0.id) }
            await runScan(coveringLocations: affected) { scanner, progress in
                try await scanner.scanLocations(affected, forceReparse: false, progress: progress)
            }
        }
    }

    // MARK: - Volume Monitoring

    func startVolumeMonitoring() {
        // Idempotent: the WindowGroup .task re-runs on every window open, and the
        // old monitor's DA callbacks hold an unretained pointer to it.
        guard volumeMonitor == nil else { return }
        volumeMonitor = VolumeMonitor(
            onMount: { [weak self] url, name in
                Task { @MainActor [weak self] in
                    await self?.handleVolumeMounted(url: url, name: name)
                }
            },
            onUnmount: { [weak self] url, name in
                Task { @MainActor [weak self] in
                    self?.handleVolumeUnmounted(url: url, name: name)
                }
            }
        )
        volumeMonitor?.start()

        // DiskArbitration doesn't reliably report Finder ejects (volume unmounted,
        // device still attached). The NSWorkspace notifications do.
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            let name = (note.userInfo?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String) ?? url.lastPathComponent
            Task { @MainActor [weak self] in
                await self?.handleVolumeMounted(url: url, name: name)
            }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            let name = (note.userInfo?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String) ?? url.lastPathComponent
            Task { @MainActor [weak self] in
                self?.handleVolumeUnmounted(url: url, name: name)
            }
        })
    }

    func stopVolumeMonitoring() {
        volumeMonitor?.stop()
        volumeMonitor = nil
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func handleVolumeMounted(url: URL, name: String) async {
        offlineVolumeNames.remove(name)

        // Only user-visible drives under /Volumes. NSWorkspace also announces
        // simulator disk images and other mounts that never hold projects.
        guard url.path.hasPrefix("/Volumes/") else { return }

        // Respect the "Scan external volumes automatically" setting
        guard UserDefaults.standard.object(forKey: "scanExternalVolumes") as? Bool ?? true else { return }

        // A single physical mount fires both DiskArbitration and NSWorkspace
        // notifications; without this guard both race saveLocation into a
        // UNIQUE(path) violation and the user gets a spurious error alert.
        guard !mountsBeingHandled.contains(url.path) else { return }
        mountsBeingHandled.insert(url.path)
        defer { mountsBeingHandled.remove(url.path) }

        if let existingLocation = try? await database.fetchLocation(byPath: url.path) {
            guard existingLocation.isEnabled else { return }
            // FSEvents needs a moment to open the just-mounted volume's journal;
            // deciding before it's ready misreads every mount as "no journal".
            var mountStat = stat()
            if stat(url.path, &mountStat) == 0 {
                _ = await waitForJournal(device: mountStat.st_dev)
            }
            // With a valid baseline the volume's journal replays everything
            // that changed since last index, with no crawl.
            let target = volumeWatchTargets().first { $0.paths.contains(existingLocation.path) }
            if existingLocation.lastScannedAt != nil, let target, storedBaseline(for: target) != nil {
                Self.watchTrace("mount \(name): replaying journal, no scan")
                ensureFileWatchers()
            } else {
                Self.watchTrace("mount \(name): no valid baseline (target: \(target != nil), scanned: \(existingLocation.lastScannedAt != nil)); scanning")
                await startLocationScan(existingLocation, forceReparse: false)
            }
        } else {
            let location = LocationRecord.autoDetected(path: url.path, displayName: name)
            do {
                try await database.saveLocation(location)
                locations.append(location)
            } catch {
                reportError("Failed to Add Location", error)
                return
            }
            await startLocationScan(location, forceReparse: false)
        }
    }

    private func handleVolumeUnmounted(url: URL, name: String) {
        // Keep the projects indexed: remembering what lives on unplugged drives
        // is the point of the index. Mark the volume offline instead.
        if volumeCounts.keys.contains(name) {
            offlineVolumeNames.insert(name)
        }
        // Stops the volume's stream; its baseline stays persisted for remount
        ensureFileWatchers()
    }
}
