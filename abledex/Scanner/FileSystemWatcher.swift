//
//  FileSystemWatcher.swift
//  abledex
//
//  Created by Brett Henderson on 07/16/26.
//

import Foundation
import CoreServices

/// One FSEvents stream over one volume's locations. Starting with a persisted
/// `sinceEventID` replays the journal through the same handler as live
/// events, including changes made while the app wasn't running.
///
/// `.device` streams take their event IDs from the volume's own journal, so
/// they stay meaningful across unmount/remount and across machines; callers
/// must validate `journalUUID(forDevice:)` before trusting a persisted ID.
///
/// @unchecked Sendable: `stream` is only mutated by start()/stop() from the
/// main actor; callbacks arrive on the private queue and read immutable state.
nonisolated final class FileSystemWatcher: @unchecked Sendable {
    struct Event: Sendable {
        /// Absolute path (device-relative callback paths are translated).
        let path: String
        let flags: FSEventStreamEventFlags

        var isDirectory: Bool { flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 }
        /// The journal couldn't represent every change (e.g. the persisted event
        /// ID predates the journal's history). The subtree must be re-crawled.
        var mustScanSubDirs: Bool { flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 }
        var wasCreated: Bool { flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 }
        var wasRemoved: Bool { flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 }
        var wasRenamed: Bool { flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 }
        /// Volume lifecycle noise; mount/unmount is handled by VolumeMonitor.
        var isMountOrUnmount: Bool {
            flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount) != 0
        }
    }

    enum Target: Equatable, Sendable {
        /// Host-wide stream over absolute paths (boot volume).
        case host(paths: [String])
        /// Stream relative to a device; paths are relative to the volume root
        /// ("" watches the whole volume).
        case device(device: dev_t, volumeRoot: String, relativePaths: [String])
    }

    let target: Target

    /// The absolute location paths this watcher covers (identity check for
    /// "already watching exactly this").
    var absolutePaths: [String] {
        switch target {
        case .host(let paths):
            return paths
        case .device(_, let volumeRoot, let relativePaths):
            return relativePaths.map { $0.isEmpty ? volumeRoot : volumeRoot + "/" + $0 }
        }
    }

    private let sinceEventID: FSEventStreamEventId
    private let latency: TimeInterval
    private let handler: @Sendable ([Event], FSEventStreamEventId) -> Void
    private let queue = DispatchQueue(label: "com.abledex.filewatcher", qos: .utility)
    private var stream: FSEventStreamRef?

    init(
        target: Target,
        sinceEventID: FSEventStreamEventId,
        latency: TimeInterval = 2.0,
        handler: @escaping @Sendable ([Event], FSEventStreamEventId) -> Void
    ) {
        self.target = target
        self.sinceEventID = sinceEventID
        self.latency = latency
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// Identifies the epoch of a volume's FSEvents journal. Persisted event IDs
    /// are only valid while this matches; a changed UUID means the journal was
    /// rebuilt and a full rescan of that volume is required. nil when the
    /// volume has no journal at all (replay impossible).
    static func journalUUID(forDevice device: dev_t) -> String? {
        guard let uuid = FSEventsCopyUUIDForDevice(device) else { return nil }
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String?
    }

    /// The device journal's most recent event ID, a "since now" baseline in
    /// the device's own ID space.
    static func lastEventID(forDevice device: dev_t) -> FSEventStreamEventId {
        FSEventsGetLastEventIdForDeviceBeforeTime(device, CFAbsoluteTimeGetCurrent())
    }

    func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)

        let callback: FSEventStreamCallback = { _, info, eventCount, eventPaths, eventFlags, eventIDs in
            guard let info, eventCount > 0 else { return }
            let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let rawPaths = Unmanaged<CFArray>.fromOpaque(UnsafeRawPointer(eventPaths))
                .takeUnretainedValue() as NSArray as? [String],
                rawPaths.count == eventCount else { return }

            var events: [Event] = []
            events.reserveCapacity(eventCount)
            for index in 0..<eventCount {
                events.append(Event(path: watcher.absolutePath(for: rawPaths[index]), flags: eventFlags[index]))
            }
            watcher.handler(events, eventIDs[eventCount - 1])
        }

        let created: FSEventStreamRef?
        switch target {
        case .host(let paths):
            guard !paths.isEmpty else { return }
            created = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &context,
                paths as CFArray, sinceEventID, latency, flags
            )
        case .device(let device, _, let relativePaths):
            created = FSEventStreamCreateRelativeToDevice(
                kCFAllocatorDefault, callback, &context,
                device, relativePaths as CFArray, sinceEventID, latency, flags
            )
        }

        guard let created else { return }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Device streams report paths relative to the volume root.
    private func absolutePath(for rawPath: String) -> String {
        guard case .device(_, let volumeRoot, _) = target else { return rawPath }
        let trimmed = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
        return trimmed.isEmpty ? volumeRoot : volumeRoot + "/" + trimmed
    }
}
