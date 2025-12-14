import Foundation
import DiskArbitration

final class VolumeMonitor: Sendable {
    private let session: DASession
    private let queue: DispatchQueue

    private let onMount: @Sendable (URL, String) -> Void
    private let onUnmount: @Sendable (URL, String) -> Void

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

    func start() {
        DASessionSetDispatchQueue(session, queue)

        // Create context for callbacks
        let contextPtr = Unmanaged.passUnretained(self).toOpaque()

        // Register for mount notifications
        DARegisterDiskAppearedCallback(
            session,
            nil, // Match all disks
            { disk, context in
                guard let context = context else { return }
                let monitor = Unmanaged<VolumeMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.handleDiskAppeared(disk)
            },
            contextPtr
        )

        // Register for unmount notifications
        DARegisterDiskDisappearedCallback(
            session,
            nil,
            { disk, context in
                guard let context = context else { return }
                let monitor = Unmanaged<VolumeMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.handleDiskDisappeared(disk)
            },
            contextPtr
        )
    }

    func stop() {
        DASessionSetDispatchQueue(session, nil)
    }

    private func handleDiskAppeared(_ disk: DADisk) {
        guard let info = DADiskCopyDescription(disk) as? [String: Any],
              let volumePath = info[kDADiskDescriptionVolumePathKey as String] as? URL,
              let volumeName = info[kDADiskDescriptionVolumeNameKey as String] as? String else {
            return
        }

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
