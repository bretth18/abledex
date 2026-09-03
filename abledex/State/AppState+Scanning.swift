//
//  AppState+Scanning.swift
//  abledex
//

import Foundation

extension AppState {
    // MARK: - Scanning

    func startScan(forceReparse: Bool = false) async {
        await runScan { scanner, progress in
            try await scanner.scanAllLocations(forceReparse: forceReparse, progress: progress)
        }
    }

    func startLocationScan(_ location: LocationRecord, forceReparse: Bool = true) async {
        await runScan(coveringLocations: [location]) { scanner, progress in
            try await scanner.scanLocation(location, forceReparse: forceReparse, progress: progress)
        }
    }

    /// Shared scan driver; the wrapping Task exists only to give Stop Scan a
    /// cancellation handle. `coveringLocations` nil = every enabled location.
    /// Volumes whose enabled locations are ALL covered get a fresh replay
    /// baseline, captured BEFORE crawling so mid-scan changes replay later.
    func runScan(
        coveringLocations: [LocationRecord]? = nil,
        _ operation: @escaping @Sendable (ProjectScanner, @escaping @Sendable (ScanProgress) -> Void) async throws -> Int
    ) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = .starting

        let coveredPaths = coveringLocations.map { Set($0.map(\.path)) }
        let freshBaselines: [(key: String, target: VolumeWatchTarget, id: FSEventStreamEventId)] =
            volumeWatchTargets().compactMap { target in
                let fullyCovered = coveredPaths.map { covered in
                    target.paths.allSatisfy { covered.contains($0) }
                } ?? true
                guard fullyCovered, let baseline = currentBaseline(for: target) else { return nil }
                return (target.key, target, baseline)
            }

        let scanner = self.scanner
        let reportProgress: @Sendable (ScanProgress) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.scanProgress = progress
            }
        }
        let task = Task { () -> Result<Int, Error> in
            do {
                return .success(try await operation(scanner, reportProgress))
            } catch {
                return .failure(error)
            }
        }
        cancelScanAction = { task.cancel() }
        let result = await task.value
        cancelScanAction = nil

        await finishScan(with: result, freshBaselines: freshBaselines)
    }

    func cancelScan() {
        cancelScanAction?()
    }

    func finishScan(
        with result: Result<Int, Error>,
        freshBaselines: [(key: String, target: VolumeWatchTarget, id: FSEventStreamEventId)]
    ) async {
        // Projects streamed in via the observation; only location metadata
        // (counts, last-scanned dates) needs a refresh.
        locations = (try? await database.fetchAllLocations()) ?? locations

        switch result {
        case .success:
            for baseline in freshBaselines {
                persistBaseline(baseline.id, for: baseline.target)
            }
            ensureFileWatchers()
        case .failure(let error):
            if error is CancellationError {
                // Batches saved before cancellation are already in the DB — show them.
                scanProgress = nil
            } else {
                reportError("Scan Failed", error)
                scanProgress = .failed(error)
            }
        }

        isScanning = false
    }

    func rescanProject(_ project: ProjectRecord) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = .parsing(current: 1, total: 1, projectName: project.name)

        let scanner = self.scanner
        let alsPath = project.alsFilePath
        let task = Task { () -> Result<ProjectRecord?, Error> in
            do {
                let record = try await scanner.scanSingleProject(alsFilePath: alsPath)
                return .success(record)
            } catch {
                return .failure(error)
            }
        }
        cancelScanAction = { task.cancel() }
        let result = await task.value
        cancelScanAction = nil

        switch result {
        case .success(let record):
            // nil record = file is gone; drop its stale index entry
            if record == nil {
                try? await database.deleteProject(byAlsFilePath: alsPath)
            }
            scanProgress = .completed(projectCount: 1, duration: 0)
        case .failure(let error):
            reportError("Rescan Failed", error)
            scanProgress = .failed(error)
        }

        isScanning = false
    }

    func rescanProjects(_ projectsToRescan: [ProjectRecord]) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = .starting

        let scanner = self.scanner
        let total = projectsToRescan.count

        var isCancelled = false
        cancelScanAction = { isCancelled = true }

        var updatedCount = 0
        var scannedCount = 0
        for project in projectsToRescan {
            if isCancelled { break }
            scannedCount += 1
            scanProgress = .parsing(current: scannedCount, total: total, projectName: project.name)

            // scanSingleProject is @concurrent — parsing runs off the main actor.
            if (try? await scanner.scanSingleProject(alsFilePath: project.alsFilePath)) != nil {
                updatedCount += 1
            }
        }
        cancelScanAction = nil

        scanProgress = isCancelled ? nil : .completed(projectCount: updatedCount, duration: 0)
        isScanning = false
    }
}
