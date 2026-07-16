//
//  VolumeMonitor.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import Foundation
import DiskArbitration
import Synchronization

final class VolumeMonitor: Sendable {
    private let session: DASession
    private let queue: DispatchQueue
    private let isMonitoring = Mutex(false)

    // DiskArbitration replays a "disk appeared" callback for every volume that
    // is already mounted when callbacks register. Those are launch noise, not
    // mounts — remember what was mounted at start() and swallow their replay.
    private let initiallyMountedPaths = Mutex<Set<String>>([])

    private let onMount: @Sendable (URL, String) -> Void
    private let onUnmount: @Sendable (URL, String) -> Void

    // Stable function pointers so register and unregister refer to the same callback
    private static let appearedCallback: DADiskAppearedCallback = { disk, context in
        guard let context = context else { return }
        let monitor = Unmanaged<VolumeMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handleDiskAppeared(disk)
    }

    private static let disappearedCallback: DADiskDisappearedCallback = { disk, context in
        guard let context = context else { return }
        let monitor = Unmanaged<VolumeMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handleDiskDisappeared(disk)
    }

    init(
        onMount: @escaping @Sendable (URL, String) -> Void,
        onUnmount: @escaping @Sendable (URL, String) -> Void
    ) {
        self.onMount = onMount
        self.onUnmount = onUnmount
        self.queue = DispatchQueue(label: "com.abledex.volumemonitor", qos: .utility)

        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            fatalError("Failed to create DiskArbitration session")
        }
        self.session = session
    }

    deinit {
        stop()
    }

    func start() {
        let alreadyMonitoring = isMonitoring.withLock { monitoring in
            defer { monitoring = true }
            return monitoring
        }
        guard !alreadyMonitoring else { return }

        let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        initiallyMountedPaths.withLock { $0 = Set(mounted.map(\.path)) }

        DASessionSetDispatchQueue(session, queue)

        // Context is passed unretained; stop() must unregister before self deallocates
        let contextPtr = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskAppearedCallback(session, nil, Self.appearedCallback, contextPtr)
        DARegisterDiskDisappearedCallback(session, nil, Self.disappearedCallback, contextPtr)
    }

    func stop() {
        let wasMonitoring = isMonitoring.withLock { monitoring in
            defer { monitoring = false }
            return monitoring
        }
        guard wasMonitoring else { return }

        let contextPtr = Unmanaged.passUnretained(self).toOpaque()
        DAUnregisterCallback(session, unsafeBitCast(Self.appearedCallback, to: UnsafeMutableRawPointer.self), contextPtr)
        DAUnregisterCallback(session, unsafeBitCast(Self.disappearedCallback, to: UnsafeMutableRawPointer.self), contextPtr)
        DASessionSetDispatchQueue(session, nil)
    }

    private func handleDiskAppeared(_ disk: DADisk) {
        guard let info = DADiskCopyDescription(disk) as? [String: Any],
              let volumePath = info[kDADiskDescriptionVolumePathKey as String] as? URL,
              let volumeName = info[kDADiskDescriptionVolumeNameKey as String] as? String else {
            return
        }

        // Swallow the registration-time replay of already-mounted disks; a
        // volume that later unmounts and reappears is a real mount again.
        let wasAlreadyMounted = initiallyMountedPaths.withLock { initial in
            initial.remove(volumePath.path) != nil
        }
        if wasAlreadyMounted { return }

        // Only user-visible drives mount under /Volumes — simulator disk
        // images and cryptexes mount elsewhere and never hold music projects.
        guard volumePath.path.hasPrefix("/Volumes/") else { return }

        // Only notify for mounted volumes (not internal system volumes)
        let isInternal = info[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? true
        let isRemovable = info[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false

        if isRemovable || !isInternal {
            onMount(volumePath, volumeName)
        }
    }

    private func handleDiskDisappeared(_ disk: DADisk) {
        guard let info = DADiskCopyDescription(disk) as? [String: Any],
              let volumePath = info[kDADiskDescriptionVolumePathKey as String] as? URL,
              let volumeName = info[kDADiskDescriptionVolumeNameKey as String] as? String else {
            return
        }

        onUnmount(volumePath, volumeName)
    }
}

// MARK: - Volume Info Helper

struct VolumeInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let path: URL
    let isRemovable: Bool
    let totalSpace: Int64?
    let freeSpace: Int64?

    var formattedTotalSpace: String? {
        guard let bytes = totalSpace else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var formattedFreeSpace: String? {
        guard let bytes = freeSpace else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension VolumeInfo {
    static func mounted() -> [VolumeInfo] {
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: volumesURL,
            includingPropertiesForKeys: [
                .volumeNameKey,
                .volumeIsRemovableKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url -> VolumeInfo? in
            guard let resourceValues = try? url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeIsRemovableKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ]) else {
                return nil
            }

            return VolumeInfo(
                id: url.path,
                name: resourceValues.volumeName ?? url.lastPathComponent,
                path: url,
                isRemovable: resourceValues.volumeIsRemovable ?? false,
                totalSpace: resourceValues.volumeTotalCapacity.map(Int64.init),
                freeSpace: resourceValues.volumeAvailableCapacity.map(Int64.init)
            )
        }
    }
}
