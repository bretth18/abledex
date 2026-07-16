//
//  FileSystemWatcher.swift
//  abledex
//
//  Created by Brett Henderson on 07/16/26.
//

import Foundation
import CoreServices

/// Thin FSEvents wrapper: watches location roots and delivers file-level
/// events (coalesced by `latency`) plus each batch's last event ID so the
/// caller can persist replay progress.
///
/// Starting a stream with a persisted `sinceEventID` replays the filesystem
/// journal — including changes made while the app wasn't running — through the
/// same handler as live events. That's what lets launch skip the full crawl.
///
/// @unchecked Sendable: `stream` is only mutated by start()/stop() (called from
/// the main actor); FSEvents delivers callbacks on the private serial queue and
/// the callback only reads immutable state.
nonisolated final class FileSystemWatcher: @unchecked Sendable {
    struct Event: Sendable {
        let path: String
        let flags: FSEventStreamEventFlags

        var isDirectory: Bool { flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 }
        /// The journal couldn't represent every change (e.g. the persisted event
        /// ID predates the journal's history) — the subtree must be re-crawled.
        var mustScanSubDirs: Bool { flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 }
        var wasCreated: Bool { flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 }
        var wasRemoved: Bool { flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 }
        var wasRenamed: Bool { flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 }
    }

    let paths: [String]
    private let sinceEventID: FSEventStreamEventId
    private let latency: TimeInterval
    private let handler: @Sendable ([Event], FSEventStreamEventId) -> Void
    private let queue = DispatchQueue(label: "com.abledex.filewatcher", qos: .utility)
    private var stream: FSEventStreamRef?

    init(
        paths: [String],
        sinceEventID: FSEventStreamEventId,
        latency: TimeInterval = 2.0,
        handler: @escaping @Sendable ([Event], FSEventStreamEventId) -> Void
    ) {
        self.paths = paths
        self.sinceEventID = sinceEventID
        self.latency = latency
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callback: FSEventStreamCallback = { _, info, eventCount, eventPaths, eventFlags, eventIDs in
            guard let info, eventCount > 0 else { return }
            let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = Unmanaged<CFArray>.fromOpaque(UnsafeRawPointer(eventPaths))
                .takeUnretainedValue() as NSArray as? [String],
                paths.count == eventCount else { return }

            var events: [Event] = []
            events.reserveCapacity(eventCount)
            for index in 0..<eventCount {
                events.append(Event(path: paths[index], flags: eventFlags[index]))
            }
            watcher.handler(events, eventIDs[eventCount - 1])
        }

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            sinceEventID,
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }

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
}
