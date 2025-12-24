//
//  StatisticsView.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import SwiftUI
import Charts

struct StatisticsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text("Stats")
                        .font(.largeTitle.bold())
                        .padding(.bottom, 8)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.accessoryBar)
                }

                // Overview cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(title: "Total Projects", value: "\(appState.projectCount)", icon: "music.note.list", color: .blue)

                    StatCard(title: "Favorites", value: "\(appState.favoritesCount)", icon: "star.fill", color: .yellow) {
                        appState.clearAllFilters()
                        appState.showFavoritesOnly = true
                        dismiss()
                    }

                    StatCard(title: "Avg BPM", value: averageBPM, icon: "metronome", color: .orange)

                    StatCard(title: "Total Duration", value: totalDuration, icon: "clock", color: .purple)
                }

                Divider()

                // Status breakdown
                VStack(alignment: .leading, spacing: 12) {
                    Text("Status Breakdown")
                        .font(.headline)

                    HStack(spacing: 24) {
                        // Chart
                        if #available(macOS 14.0, *) {
                            Chart(statusData, id: \.status) { item in
                                SectorMark(
                                    angle: .value("Count", item.count),
                                    innerRadius: .ratio(0.5),
                                    angularInset: 2
                                )
                                .foregroundStyle(item.color)
                                .annotation(position: .overlay) {
                                    if item.count > 0 {
                                        Text("\(item.count)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .frame(width: 200, height: 200)
                        }

                        // Legend (clickable)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(statusData, id: \.status) { item in
                                Button {
                                    appState.clearAllFilters()
                                    appState.selectedStatusFilter = item.status
                                    dismiss()
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(item.color)
                                            .frame(width: 12, height: 12)
                                        Text(item.status.label)
                                        Spacer()
                                        Text("\(item.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(width: 200)
                    }
                }

                Divider()

                // Storage by Volume
                VStack(alignment: .leading, spacing: 12) {
                    Text("Storage by Volume")
                        .font(.headline)

                    if storageByVolume.isEmpty {
                        Text("No volume data available")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(storageByVolume, id: \.volume) { item in
                                Button {
                                    appState.clearAllFilters()
                                    appState.selectedVolumeFilter = item.volume
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "externaldrive")
                                            .foregroundStyle(.blue)
                                        Text(item.volume)
                                        Spacer()
                                        Text("\(item.count) projects")
                                            .foregroundStyle(.secondary)
                                        Text(formatBytes(item.size))
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack {
                            Spacer()
                            Text("Total: \(formatBytes(totalStorageSize))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // Key Distribution
                VStack(alignment: .leading, spacing: 12) {
                    Text("Key Distribution")
                        .font(.headline)

                    if keyDistribution.isEmpty {
                        Text("No key data available")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(keyDistribution.prefix(12), id: \.key) { item in
                                Button {
                                    appState.clearAllFilters()
                                    appState.selectedKeyFilter = item.key
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.key)
                                                .font(.caption)
                                            if let camelot = item.camelot {
                                                Text(camelot)
                                                    .font(.caption2)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        Spacer()
                                        Text("\(item.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(.quaternary.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Divider()

                // BPM distribution
                VStack(alignment: .leading, spacing: 12) {
                    Text("BPM Distribution")
                        .font(.headline)

                    if #available(macOS 14.0, *) {
                        Chart(bpmDistribution, id: \.range) { item in
                            BarMark(
                                x: .value("BPM Range", item.range),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(.blue.gradient)
                        }
                        .frame(height: 200)
                    } else {
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(bpmDistribution, id: \.range) { item in
                                VStack {
                                    Text("\(item.count)")
                                        .font(.caption2)
                                    Rectangle()
                                        .fill(.blue)
                                        .frame(width: 40, height: CGFloat(item.count) * 5)
                                    Text(item.range)
                                        .font(.caption2)
                                        .rotationEffect(.degrees(-45))
                                }
                            }
                        }
                        .frame(height: 200)
                    }
                }

                Divider()

                // Activity Trends
                VStack(alignment: .leading, spacing: 12) {
                    Text("Activity Trends")
                        .font(.headline)

                    HStack(spacing: 24) {
                        // Weekly chart
                        if #available(macOS 14.0, *) {
                            VStack(alignment: .leading) {
                                Text("Projects Created (Last 6 Months)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Chart(projectsByWeek, id: \.week) { item in
                                    AreaMark(
                                        x: .value("Week", item.week, unit: .weekOfYear),
                                        y: .value("Count", item.count)
                                    )
                                    .foregroundStyle(.green.opacity(0.3))

                                    LineMark(
                                        x: .value("Week", item.week, unit: .weekOfYear),
                                        y: .value("Count", item.count)
                                    )
                                    .foregroundStyle(.green)
                                }
                                .frame(height: 150)
                            }
                        }

                        // Day of week breakdown
                        VStack(alignment: .leading, spacing: 8) {
                            Text("By Day of Week")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ForEach(projectsByDayOfWeek, id: \.day) { item in
                                HStack {
                                    Text(item.day)
                                        .font(.caption)
                                        .frame(width: 40, alignment: .leading)
                                    GeometryReader { geometry in
                                        let maxCount = Double(projectsByDayOfWeek.map(\.count).max() ?? 1)
                                        let width = maxCount > 0 ? (Double(item.count) / maxCount) * geometry.size.width : 0
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(.green.gradient)
                                            .frame(width: max(0, width), height: 16)
                                    }
                                    .frame(height: 16)
                                    Text("\(item.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 30, alignment: .trailing)
                                }
                            }
                        }
                        .frame(width: 200)
                    }

                    HStack(spacing: 16) {
                        StatMiniCard(title: "Most Productive", value: mostProductiveDay, icon: "flame")
                        StatMiniCard(title: "Avg/Week", value: averageProjectsPerWeek, icon: "chart.line.uptrend.xyaxis")
                    }
                }

                Divider()

                // Top plugins
                VStack(alignment: .leading, spacing: 12) {
                    Text("Most Used Plugins")
                        .font(.headline)

                    if topPlugins.isEmpty {
                        Text("No plugin data available")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(topPlugins.prefix(10), id: \.name) { plugin in
                                Button {
                                    appState.clearAllFilters()
                                    appState.selectedPluginFilter = plugin.name
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "puzzlepiece.extension")
                                            .foregroundStyle(.orange)
                                        Text(plugin.name)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(plugin.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Divider()

                // Projects over time
                VStack(alignment: .leading, spacing: 12) {
                    Text("Projects by Month")
                        .font(.headline)

                    if #available(macOS 14.0, *) {
                        Chart(projectsByMonth, id: \.month) { item in
                            BarMark(
                                x: .value("Month", item.month, unit: .month),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(.blue.gradient)
                        }
                        .frame(height: 200)
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 600, idealHeight: 700)
    }

    // MARK: - Computed Stats

    private var averageBPM: String {
        let bpms = appState.projects.compactMap { $0.bpm }
        guard !bpms.isEmpty else { return "-" }
        let avg = bpms.reduce(0, +) / Double(bpms.count)
        return String(format: "%.0f", avg)
    }

    private var totalDuration: String {
        let total = appState.projects.compactMap { $0.duration }.reduce(0, +)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private var statusData: [(status: CompletionStatus, count: Int, color: Color)] {
        CompletionStatus.allCases.map { status in
            let count = appState.projects.filter { $0.completionStatus == status }.count
            let color: Color = {
                switch status {
                case .none: return .gray
                case .idea: return .yellow
                case .inProgress: return .blue
                case .mixing: return .purple
                case .done: return .green
                }
            }()
            return (status, count, color)
        }
    }

    private var bpmDistribution: [(range: String, count: Int)] {
        let ranges = [
            ("< 80", 0..<80),
            ("80-99", 80..<100),
            ("100-119", 100..<120),
            ("120-139", 120..<140),
            ("140-159", 140..<160),
            ("160+", 160..<500)
        ]

        return ranges.map { (label, range) in
            let count = appState.projects.filter { project in
                guard let bpm = project.bpm else { return false }
                return range.contains(Int(bpm))
            }.count
            return (label, count)
        }
    }

    private var topPlugins: [(name: String, count: Int)] {
        var pluginCounts: [String: Int] = [:]
        for project in appState.projects {
            for plugin in project.plugins {
                pluginCounts[plugin, default: 0] += 1
            }
        }
        return pluginCounts
            .map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
    }

    private var projectsByMonth: [(month: Date, count: Int)] {
        let calendar = Calendar.current
        var monthCounts: [Date: Int] = [:]

        for project in appState.projects {
            let date = project.createdDate ?? project.filesystemModifiedDate
            if let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) {
                monthCounts[monthStart, default: 0] += 1
            }
        }

        return monthCounts
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
            .suffix(12)
            .map { $0 }
    }

    // MARK: - Storage Stats

    private var totalStorageSize: Int64 {
        appState.projects.reduce(Int64(0)) { sum, project in
            let url = URL(fileURLWithPath: project.alsFilePath)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                return sum + Int64(size)
            }
            return sum
        }
    }

    private var storageByVolume: [(volume: String, size: Int64, count: Int)] {
        let grouped = Dictionary(grouping: appState.projects, by: { $0.sourceVolume })
        return grouped.map { (volume, projects) in
            let size = projects.reduce(Int64(0)) { sum, project in
                let url = URL(fileURLWithPath: project.alsFilePath)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fileSize = attrs[.size] as? UInt64 {
                    return sum + Int64(fileSize)
                }
                return sum
            }
            return (volume, size, projects.count)
        }.sorted { $0.size > $1.size }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Key Distribution

    private var keyDistribution: [(key: String, camelot: String?, count: Int)] {
        var keyCounts: [String: Int] = [:]
        for project in appState.projects {
            for key in project.musicalKeys {
                keyCounts[key, default: 0] += 1
            }
        }
        return keyCounts
            .map { (key: $0.key, camelot: CamelotConverter.toCamelot($0.key), count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Activity Trends

    private var projectsByWeek: [(week: Date, count: Int)] {
        let calendar = Calendar.current
        var weekCounts: [Date: Int] = [:]

        for project in appState.projects {
            let date = project.createdDate ?? project.filesystemModifiedDate
            if let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) {
                weekCounts[weekStart, default: 0] += 1
            }
        }

        return weekCounts
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
            .suffix(24)
            .map { $0 }
    }

    private var projectsByDayOfWeek: [(day: String, count: Int)] {
        let calendar = Calendar.current
        var dayCounts: [Int: Int] = [:]

        for project in appState.projects {
            let date = project.createdDate ?? project.filesystemModifiedDate
            let weekday = calendar.component(.weekday, from: date)
            dayCounts[weekday, default: 0] += 1
        }

        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (1...7).map { (dayNames[$0], dayCounts[$0] ?? 0) }
    }

    private var mostProductiveDay: String {
        projectsByDayOfWeek.max(by: { $0.count < $1.count })?.day ?? "-"
    }

    private var averageProjectsPerWeek: String {
        guard !projectsByWeek.isEmpty else { return "-" }
        let total = projectsByWeek.reduce(0) { $0 + $1.count }
        let avg = Double(total) / Double(projectsByWeek.count)
        return String(format: "%.1f", avg)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.title.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

// MARK: - Stat Mini Card

struct StatMiniCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(value)
                    .font(.headline)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
