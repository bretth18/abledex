//
//  NSTableViewBridge.swift
//  abledex
//
//  Created by Brett Henderson on 4/4/26.
//

import AppKit
import SwiftUI

// MARK: - Column Definitions

enum ProjectTableColumn: String, CaseIterable {
    case favorite = "favorite"
    case name = "name"
    case status = "status"
    case bpm = "bpm"
    case created = "created"
    case modified = "modified"
    case tracks = "tracks"
    case duration = "duration"
    case version = "version"
    case volume = "volume"

    var title: String {
        switch self {
        case .favorite: return ""
        case .name: return "Name"
        case .status: return "Status"
        case .bpm: return "BPM"
        case .created: return "Created"
        case .modified: return "Modified"
        case .tracks: return "Tracks"
        case .duration: return "Duration"
        case .version: return "Version"
        case .volume: return "Volume"
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .favorite: return 24
        case .name: return 150
        case .status: return 80
        case .bpm: return 50
        case .created: return 80
        case .modified: return 80
        case .tracks: return 60
        case .duration: return 60
        case .version: return 60
        case .volume: return 80
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .favorite: return 24
        case .name: return 200
        case .status: return 100
        case .bpm: return 50
        case .created: return 100
        case .modified: return 100
        case .tracks: return 80
        case .duration: return 60
        case .version: return 60
        case .volume: return 120
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .favorite: return 24
        case .name: return .greatestFiniteMagnitude
        case .status: return 140
        case .bpm: return 60
        case .created: return 140
        case .modified: return 140
        case .tracks: return 100
        case .duration: return 80
        case .version: return 80
        case .volume: return 180
        }
    }

    var sortColumn: SortColumn? {
        switch self {
        case .favorite: return nil
        case .name: return .name
        case .status: return .status
        case .bpm: return .bpm
        case .created: return .createdDate
        case .modified: return .modifiedDate
        case .tracks: return .tracks
        case .duration: return .duration
        case .version: return .version
        case .volume: return nil
        }
    }
}

// MARK: - SwiftUI Bridge

struct ProjectNSTableView: NSViewRepresentable {
    let projects: [ProjectRecord]
    let selection: Set<UUID>
    let sortColumn: SortColumn
    let sortAscending: Bool
    let alternatesRowBackgrounds: Bool
    let onSelectionChanged: (Set<UUID>) -> Void
    let onFavoriteToggle: (ProjectRecord) -> Void
    let onOpenProject: (ProjectRecord) -> Void
    let onRevealProject: (ProjectRecord) -> Void
    let onDeleteProjects: (Set<UUID>) -> Void
    let onSetStatus: (ProjectRecord, CompletionStatus) -> Void
    let onRescanProject: (ProjectRecord) -> Void
    let theme: AppTheme

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let tableView = NSTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = alternatesRowBackgrounds
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 6, height: 0)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.usesAutomaticRowHeights = false
        tableView.gridStyleMask = []
        tableView.headerView = NSTableHeaderView()

        // Register cell identifiers and add columns
        for column in ProjectTableColumn.allCases {
            let nsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            nsColumn.title = column.title
            nsColumn.minWidth = column.minWidth
            nsColumn.width = column.idealWidth
            nsColumn.maxWidth = column.maxWidth
            nsColumn.isEditable = false

            if let sort = column.sortColumn {
                nsColumn.sortDescriptorPrototype = NSSortDescriptor(
                    key: sort.rawValue,
                    ascending: sort == .name
                )
            }

            tableView.addTableColumn(nsColumn)
        }

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        // Double-click to open
        tableView.doubleAction = #selector(Coordinator.doubleClickRow(_:))
        tableView.target = context.coordinator

        // Context menu
        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = context.coordinator.tableView else { return }
        let coordinator = context.coordinator

        // Diff and update
        let oldProjects = coordinator.currentProjects
        let newProjects = projects

        coordinator.parent = self
        coordinator.currentProjects = newProjects

        // Update alternating rows
        tableView.usesAlternatingRowBackgroundColors = alternatesRowBackgrounds

        // Smart reload: if just data changed (same count, same IDs in order), reload visible rows only
        if oldProjects.count == newProjects.count,
           oldProjects.map(\.id) == newProjects.map(\.id) {
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            if visibleRange.length > 0 {
                let columnRange = NSRange(location: 0, length: tableView.numberOfColumns)
                tableView.reloadData(
                    forRowIndexes: IndexSet(integersIn: visibleRange.location..<(visibleRange.location + visibleRange.length)),
                    columnIndexes: IndexSet(integersIn: columnRange.location..<(columnRange.location + columnRange.length))
                )
            }
        } else {
            tableView.reloadData()
        }

        // Sync selection without triggering delegate callback
        coordinator.isSyncingSelection = true
        let targetIndexes = NSMutableIndexSet()
        for (index, project) in newProjects.enumerated() {
            if selection.contains(project.id) {
                targetIndexes.add(index)
            }
        }
        if tableView.selectedRowIndexes != IndexSet(targetIndexes) {
            tableView.selectRowIndexes(IndexSet(targetIndexes), byExtendingSelection: false)
        }
        coordinator.isSyncingSelection = false

        // Sync sort indicators
        for nsColumn in tableView.tableColumns {
            guard let colId = ProjectTableColumn(rawValue: nsColumn.identifier.rawValue),
                  let sort = colId.sortColumn else {
                tableView.setIndicatorImage(nil, in: nsColumn)
                continue
            }
            if sort == sortColumn {
                let image = NSImage(systemSymbolName: sortAscending ? "chevron.up" : "chevron.down",
                                    accessibilityDescription: sortAscending ? "Ascending" : "Descending")
                tableView.setIndicatorImage(image, in: nsColumn)
                tableView.highlightedTableColumn = nsColumn
            } else {
                tableView.setIndicatorImage(nil, in: nsColumn)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        var parent: ProjectNSTableView
        var tableView: NSTableView?
        var currentProjects: [ProjectRecord] = []
        var isSyncingSelection = false

        // Reusable formatters (allocated once)
        private let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f
        }()
        private let relativeDateFormatter: RelativeDateTimeFormatter = {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return f
        }()

        init(parent: ProjectNSTableView) {
            self.parent = parent
        }

        // MARK: - DataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            currentProjects.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn,
                  let column = ProjectTableColumn(rawValue: tableColumn.identifier.rawValue),
                  row < currentProjects.count else { return nil }

            let project = currentProjects[row]
            let cellID = tableColumn.identifier

            // Reuse or create cell
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = makeCell(for: column, identifier: cellID)
            }

            configure(cell: cell, column: column, project: project)
            return cell
        }

        // MARK: - Cell Factory

        private func makeCell(for column: ProjectTableColumn, identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            switch column {
            case .favorite:
                return makeFavoriteCell(identifier: identifier)
            case .name:
                return makeNameCell(identifier: identifier)
            case .tracks:
                return makeTracksCell(identifier: identifier)
            default:
                return makeIconTextCell(identifier: identifier)
            }
        }

        /// Standard icon + text cell used by most columns
        private func makeIconTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            textField.textColor = .secondaryLabelColor
            textField.translatesAutoresizingMaskIntoConstraints = false

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            imageView.isHidden = true
            imageView.imageScaling = .scaleProportionallyDown

            cell.addSubview(imageView)
            cell.addSubview(textField)
            cell.textField = textField
            cell.imageView = imageView

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 12),
                imageView.heightAnchor.constraint(equalToConstant: 12),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 3),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])

            return cell
        }

        /// Name column: icon + title with inline "Missing samples" indicator
        private func makeNameCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            imageView.imageScaling = .scaleProportionallyDown

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.cell?.truncatesLastVisibleLine = true

            cell.addSubview(imageView)
            cell.addSubview(textField)
            cell.textField = textField
            cell.imageView = imageView

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 12),
                imageView.heightAnchor.constraint(equalToConstant: 12),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 3),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])

            return cell
        }

        private func makeFavoriteCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let button = NSButton()
            button.bezelStyle = .inline
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.translatesAutoresizingMaskIntoConstraints = false
            button.target = self
            button.action = #selector(favoriteClicked(_:))

            cell.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 16),
                button.heightAnchor.constraint(equalToConstant: 16),
            ])

            return cell
        }

        /// Tracks column: uses a single attributed string with inline SF Symbol images
        private func makeTracksCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            textField.textColor = .secondaryLabelColor
            textField.translatesAutoresizingMaskIntoConstraints = false

            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])

            return cell
        }

        // MARK: - Cell Configuration

        private func configure(cell: NSTableCellView, column: ProjectTableColumn, project: ProjectRecord) {
            switch column {
            case .favorite:
                configureFavorite(cell: cell, project: project)
            case .name:
                configureName(cell: cell, project: project)
            case .status:
                configureStatus(cell: cell, project: project)
            case .bpm:
                configureBPM(cell: cell, project: project)
            case .created:
                configureCreated(cell: cell, project: project)
            case .modified:
                configureModified(cell: cell, project: project)
            case .tracks:
                configureTracks(cell: cell, project: project)
            case .duration:
                configureDuration(cell: cell, project: project)
            case .version:
                configureVersion(cell: cell, project: project)
            case .volume:
                configureVolume(cell: cell, project: project)
            }
        }

        private func configureFavorite(cell: NSTableCellView, project: ProjectRecord) {
            guard let button = cell.subviews.first(where: { $0 is NSButton }) as? NSButton else { return }
            let symbolName = project.isFavorite ? "star.fill" : "star"
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Favorite")
            button.image = image
            button.contentTintColor = project.isFavorite ? .systemYellow : .secondaryLabelColor
            button.tag = currentProjects.firstIndex(where: { $0.id == project.id }) ?? -1
        }

        private func configureName(cell: NSTableCellView, project: ProjectRecord) {
            let nameColor = NSColor(project.colorLabel.color)

            if project.hasMissingSamples {
                // Attributed string: "ProjectName  ⚠ Missing samples"
                let str = NSMutableAttributedString(
                    string: project.name,
                    attributes: [.foregroundColor: nameColor, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                )
                str.append(NSAttributedString(string: "  "))
                let attachment = NSTextAttachment()
                attachment.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")?
                    .withSymbolConfiguration(.init(pointSize: 9, weight: .regular))
                let iconStr = NSMutableAttributedString(attachment: attachment)
                iconStr.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: NSRange(location: 0, length: iconStr.length))
                str.append(iconStr)
                str.append(NSAttributedString(
                    string: " Missing samples",
                    attributes: [.foregroundColor: NSColor.systemOrange, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1)]
                ))
                cell.textField?.attributedStringValue = str
            } else {
                cell.textField?.stringValue = project.name
                cell.textField?.textColor = nameColor
            }

            let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
            cell.imageView?.image = image
            cell.imageView?.isHidden = false
            cell.imageView?.contentTintColor = project.colorLabel.rawValue != 0
                ? NSColor(project.colorLabel.color)
                : .secondaryLabelColor
        }

        private func configureStatus(cell: NSTableCellView, project: ProjectRecord) {
            let status = project.completionStatus
            cell.textField?.stringValue = status.label
            cell.textField?.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

            let image = NSImage(systemSymbolName: status.icon, accessibilityDescription: status.label)
            cell.imageView?.image = image
            cell.imageView?.isHidden = false
            cell.imageView?.contentTintColor = NSColor(parent.theme.statusColor(for: status))
        }

        private func configureBPM(cell: NSTableCellView, project: ProjectRecord) {
            if let bpm = project.bpm {
                cell.textField?.stringValue = String(format: "%.0f", bpm)
                cell.textField?.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                cell.textField?.textColor = .labelColor
            } else {
                cell.textField?.stringValue = "-"
                cell.textField?.textColor = .secondaryLabelColor
            }
            cell.imageView?.isHidden = true
        }

        private func configureCreated(cell: NSTableCellView, project: ProjectRecord) {
            if let date = project.createdDate {
                cell.textField?.stringValue = dateFormatter.string(from: date)
                cell.textField?.textColor = .secondaryLabelColor
            } else {
                cell.textField?.stringValue = "-"
                cell.textField?.textColor = .tertiaryLabelColor
            }
            cell.imageView?.isHidden = true
        }

        private func configureModified(cell: NSTableCellView, project: ProjectRecord) {
            let date = project.modifiedDate ?? project.filesystemModifiedDate
            cell.textField?.stringValue = relativeDateFormatter.localizedString(for: date, relativeTo: Date())
            cell.textField?.textColor = .secondaryLabelColor
            cell.imageView?.isHidden = true
        }

        private func configureTracks(cell: NSTableCellView, project: ProjectRecord) {
            let str = NSMutableAttributedString()
            let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            let color = NSColor.secondaryLabelColor

            if project.audioTrackCount > 0 {
                let attachment = NSTextAttachment()
                attachment.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Audio")?
                    .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
                let icon = NSMutableAttributedString(attachment: attachment)
                icon.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: icon.length))
                str.append(icon)
                str.append(NSAttributedString(string: "\(project.audioTrackCount)", attributes: [.font: font, .foregroundColor: color]))
            }
            if project.midiTrackCount > 0 {
                if str.length > 0 { str.append(NSAttributedString(string: " ")) }
                let attachment = NSTextAttachment()
                attachment.image = NSImage(systemSymbolName: "pianokeys", accessibilityDescription: "MIDI")?
                    .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
                let icon = NSMutableAttributedString(attachment: attachment)
                icon.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: icon.length))
                str.append(icon)
                str.append(NSAttributedString(string: "\(project.midiTrackCount)", attributes: [.font: font, .foregroundColor: color]))
            }
            cell.textField?.attributedStringValue = str
        }

        private func configureDuration(cell: NSTableCellView, project: ProjectRecord) {
            if let duration = project.formattedDuration {
                cell.textField?.stringValue = duration
                cell.textField?.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                cell.textField?.textColor = .secondaryLabelColor
            } else {
                cell.textField?.stringValue = "-"
                cell.textField?.textColor = .tertiaryLabelColor
            }
            cell.imageView?.isHidden = true
        }

        private func configureVersion(cell: NSTableCellView, project: ProjectRecord) {
            cell.textField?.stringValue = project.abletonVersion ?? "-"
            cell.textField?.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            cell.textField?.textColor = project.abletonVersion != nil ? .secondaryLabelColor : .tertiaryLabelColor
            cell.imageView?.isHidden = true
        }

        private func configureVolume(cell: NSTableCellView, project: ProjectRecord) {
            let iconName = project.sourceVolume == "Macintosh HD" ? "internaldrive" : "externaldrive"
            let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            cell.imageView?.image = image
            cell.imageView?.isHidden = false
            cell.imageView?.contentTintColor = .secondaryLabelColor

            cell.textField?.stringValue = project.sourceVolume
            cell.textField?.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        }

        // MARK: - Delegate

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let tableView else { return }
            let selectedIDs = Set(tableView.selectedRowIndexes.compactMap { index -> UUID? in
                guard index < currentProjects.count else { return nil }
                return currentProjects[index].id
            })
            parent.onSelectionChanged(selectedIDs)
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            // Handled by SwiftUI binding via sort column sync
        }

        // MARK: - Actions

        @objc func doubleClickRow(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < currentProjects.count else { return }
            parent.onOpenProject(currentProjects[row])
        }

        @objc func favoriteClicked(_ sender: NSButton) {
            let row = sender.tag
            guard row >= 0, row < currentProjects.count else { return }
            parent.onFavoriteToggle(currentProjects[row])
        }

        // MARK: - Context Menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }

            let clickedRow = tableView.clickedRow
            guard clickedRow >= 0, clickedRow < currentProjects.count else { return }

            let project = currentProjects[clickedRow]
            let selectedRows = tableView.selectedRowIndexes
            let isMulti = selectedRows.count > 1

            if isMulti {
                menu.addItem(withTitle: "Open \(selectedRows.count) Projects in Ableton",
                             action: #selector(openSelected(_:)), keyEquivalent: "")
                menu.addItem(withTitle: "Reveal \(selectedRows.count) Projects in Finder",
                             action: #selector(revealSelected(_:)), keyEquivalent: "")
                menu.addItem(.separator())

                let statusMenu = NSMenu()
                for status in CompletionStatus.allCases {
                    let item = NSMenuItem(title: status.label, action: #selector(setStatusFromMenu(_:)), keyEquivalent: "")
                    item.image = NSImage(systemSymbolName: status.icon, accessibilityDescription: nil)
                    item.tag = status.rawValue
                    item.target = self
                    statusMenu.addItem(item)
                }
                let statusItem = NSMenuItem(title: "Set Status", action: nil, keyEquivalent: "")
                statusItem.submenu = statusMenu
                menu.addItem(statusItem)

                menu.addItem(.separator())
                let deleteItem = NSMenuItem(title: "Remove \(selectedRows.count) Projects from Library",
                                            action: #selector(deleteSelected(_:)), keyEquivalent: "")
                deleteItem.target = self
                menu.addItem(deleteItem)
            } else {
                let openItem = NSMenuItem(title: "Open in Ableton", action: #selector(openClicked(_:)), keyEquivalent: "")
                openItem.representedObject = project.id
                openItem.target = self
                menu.addItem(openItem)

                let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealClicked(_:)), keyEquivalent: "")
                revealItem.representedObject = project.id
                revealItem.target = self
                menu.addItem(revealItem)

                menu.addItem(.separator())

                let favTitle = project.isFavorite ? "Remove from Favorites" : "Add to Favorites"
                let favItem = NSMenuItem(title: favTitle, action: #selector(toggleFavoriteClicked(_:)), keyEquivalent: "")
                favItem.representedObject = project.id
                favItem.target = self
                menu.addItem(favItem)

                let statusMenu = NSMenu()
                for status in CompletionStatus.allCases {
                    let item = NSMenuItem(title: status.label, action: #selector(setStatusSingleFromMenu(_:)), keyEquivalent: "")
                    item.image = NSImage(systemSymbolName: status.icon, accessibilityDescription: nil)
                    item.tag = status.rawValue
                    item.representedObject = project.id
                    item.target = self
                    if project.completionStatus == status {
                        item.state = .on
                    }
                    statusMenu.addItem(item)
                }
                let statusItem = NSMenuItem(title: "Set Status", action: nil, keyEquivalent: "")
                statusItem.submenu = statusMenu
                menu.addItem(statusItem)

                let rescanItem = NSMenuItem(title: "Re-scan Project", action: #selector(rescanClicked(_:)), keyEquivalent: "")
                rescanItem.representedObject = project.id
                rescanItem.target = self
                menu.addItem(rescanItem)

                menu.addItem(.separator())

                let copyItem = NSMenuItem(title: "Copy Path", action: #selector(copyPath(_:)), keyEquivalent: "")
                copyItem.representedObject = project.folderPath
                copyItem.target = self
                menu.addItem(copyItem)

                menu.addItem(.separator())

                let deleteItem = NSMenuItem(title: "Remove from Library", action: #selector(deleteSingle(_:)), keyEquivalent: "")
                deleteItem.representedObject = project.id
                deleteItem.target = self
                menu.addItem(deleteItem)
            }

            // Set targets for multi-select items
            for item in menu.items where item.target == nil && item.action != nil {
                item.target = self
            }
        }

        // MARK: - Menu Actions

        @objc func openClicked(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID,
                  let project = currentProjects.first(where: { $0.id == id }) else { return }
            parent.onOpenProject(project)
        }

        @objc func revealClicked(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID,
                  let project = currentProjects.first(where: { $0.id == id }) else { return }
            parent.onRevealProject(project)
        }

        @objc func toggleFavoriteClicked(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID,
                  let project = currentProjects.first(where: { $0.id == id }) else { return }
            parent.onFavoriteToggle(project)
        }

        @objc func setStatusSingleFromMenu(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID,
                  let project = currentProjects.first(where: { $0.id == id }),
                  let status = CompletionStatus(rawValue: sender.tag) else { return }
            parent.onSetStatus(project, status)
        }

        @objc func rescanClicked(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID,
                  let project = currentProjects.first(where: { $0.id == id }) else { return }
            parent.onRescanProject(project)
        }

        @objc func copyPath(_ sender: NSMenuItem) {
            guard let path = sender.representedObject as? String else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }

        @objc func openSelected(_ sender: NSMenuItem) {
            guard let tableView else { return }
            for index in tableView.selectedRowIndexes where index < currentProjects.count {
                parent.onOpenProject(currentProjects[index])
            }
        }

        @objc func revealSelected(_ sender: NSMenuItem) {
            guard let tableView else { return }
            for index in tableView.selectedRowIndexes where index < currentProjects.count {
                parent.onRevealProject(currentProjects[index])
            }
        }

        @objc func setStatusFromMenu(_ sender: NSMenuItem) {
            guard let tableView, let status = CompletionStatus(rawValue: sender.tag) else { return }
            for index in tableView.selectedRowIndexes where index < currentProjects.count {
                parent.onSetStatus(currentProjects[index], status)
            }
        }

        @objc func deleteSelected(_ sender: NSMenuItem) {
            guard let tableView else { return }
            let ids = Set(tableView.selectedRowIndexes.compactMap { index -> UUID? in
                guard index < currentProjects.count else { return nil }
                return currentProjects[index].id
            })
            parent.onDeleteProjects(ids)
        }

        @objc func deleteSingle(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else { return }
            parent.onDeleteProjects([id])
        }
    }
}
