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
    @Environment(\.theme) private var theme

    // Cached storage data to avoid synchronous file I/O on every render
    @State private var cachedStorageByVolume: [(volume: String, size: Int64, count: Int)] = []
    @State private var cachedTotalStorage: Int64 = 0
    @State private var isLoadingStorage = true

    // Cached derived stats to avoid recomputing aggregations on every render
    @State private var stats = ProjectStats()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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

                    StatCard(title: "Avg BPM", value: stats.averageBPM, icon: "metronome", color: .orange)

                    StatCard(title: "Total Duration", value: stats.totalDuration, icon: "clock", color: .purple)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Status Breakdown")
                        .font(.headline)

                    HStack(spacing: 24) {
                        Chart(stats.statusData, id: \.status) { item in
                            SectorMark(
                                angle: .value("Count", item.count),
                                innerRadius: .ratio(0.5),
                                angularInset: 2
                            )
                            .foregroundStyle(theme.statusColor(for: item.status))
                            .annotation(position: .overlay) {
                                if item.count > 0 {
                                    Text("\(item.count)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .frame(width: 200, height: 200)

                        // Legend (clickable)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(stats.statusData, id: \.status) { item in
                                Button {
                                    appState.clearAllFilters()
                                    appState.selectedStatusFilter = item.status
                                    dismiss()
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(theme.statusColor(for: item.status))
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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Storage by Volume")
                        .font(.headline)

                    if isLoadingStorage {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Calculating storage...")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    } else if cachedStorageByVolume.isEmpty {
                        Text("No volume data available")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(cachedStorageByVolume, id: \.volume) { item in
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
                            Text("Total: \(formatBytes(cachedTotalStorage))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Key Distribution")
                        .font(.headline)

                    if stats.keyDistribution.isEmpty {
                        Text("No key data available")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(stats.keyDistribution.prefix(12), id: \.key) { item in
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
                                    .themedCard(cornerRadius: 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("BPM Distribution")
                        .font(.headline)

                    Chart(stats.bpmDistribution, id: \.range) { item in
                        BarMark(
                            x: .value("BPM Range", item.range),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(theme.chartPrimary.gradient)
                    }
                    .frame(height: 200)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Activity Trends")
                        .font(.headline)

                    HStack(spacing: 24) {
                        VStack(alignment: .leading) {
                            Text("Projects Created (Last 6 Months)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Chart(stats.projectsByWeek, id: \.week) { item in
                                AreaMark(
                                    x: .value("Week", item.week, unit: .weekOfYear),
                                    y: .value("Count", item.count)
                                )
                                .foregroundStyle(theme.chartSecondary.opacity(0.3))

                                LineMark(
                                    x: .value("Week", item.week, unit: .weekOfYear),
                                    y: .value("Count", item.count)
                                )
                                .foregroundStyle(theme.chartSecondary)
                            }
                            .frame(height: 150)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("By Day of Week")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ForEach(stats.projectsByDayOfWeek, id: \.day) { item in
                                HStack {
                                    Text(item.day)
                                        .font(.caption)
                                        .frame(width: 40, alignment: .leading)
                                    GeometryReader { geometry in
                                        let maxCount = Double(stats.maxProjectsPerDayOfWeek)
                                        let width = maxCount > 0 ? (Double(item.count) / maxCount) * geometry.size.width : 0
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(theme.chartSecondary.gradient)
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
                        StatMiniCard(title: "Most Productive", value: stats.mostProductiveDay, icon: "flame")
                        StatMiniCard(title: "Avg/Week", value: stats.averageProjectsPerWeek, icon: "chart.line.uptrend.xyaxis")
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Most Used Plugins")
                        .font(.headline)

                    if stats.topPlugins.isEmpty {
                        Text("No plugin data available")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(stats.topPlugins.prefix(10), id: \.name) { plugin in
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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Projects by Month")
                        .font(.headline)

                    Chart(stats.projectsByMonth, id: \.month) { item in
                        BarMark(
                            x: .value("Month", item.month, unit: .month),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(theme.chartPrimary.gradient)
                    }
                    .frame(height: 200)
                }
            }
            .padding()
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 600, idealHeight: 700)
        .background(theme.usesCustomBackground ? theme.background.ignoresSafeArea() : nil)
        .task(id: statsTaskID) {
            await computeStats()
            await loadStorageData()
        }
    }

    // MARK: - Stats Invalidation

    /// Cheap Equatable key that changes whenever projects are added, removed, or re-indexed.
    private struct StatsTaskID: Equatable {
        let projectCount: Int
        let latestIndexDate: Date?
    }

    private var statsTaskID: StatsTaskID {
        StatsTaskID(
            projectCount: appState.projects.count,
            latestIndexDate: appState.projects.map(\.lastIndexedAt).max()
        )
    }

    // MARK: - Async Stats Computation

    private func computeStats() async {
        let projects = appState.projects
        stats = await Task.detached(priority: .userInitiated) {
            ProjectStats(projects: projects)
        }.value
    }

    // MARK: - Async Storage Loading

    private func loadStorageData() async {
        let projects = appState.projects
        let result = await Task.detached(priority: .userInitiated) {
            var byVolume: [String: (size: Int64, count: Int)] = [:]
            var total: Int64 = 0

            for project in projects {
                let url = URL(fileURLWithPath: project.alsFilePath)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? UInt64 {
                    let sizeInt64 = Int64(size)
                    total += sizeInt64

                    let volume = project.sourceVolume
                    if let existing = byVolume[volume] {
                        byVolume[volume] = (existing.size + sizeInt64, existing.count + 1)
                    } else {
                        byVolume[volume] = (sizeInt64, 1)
                    }
                }
            }

            let sorted = byVolume.map { (volume: $0.key, size: $0.value.size, count: $0.value.count) }
                .sorted { $0.size > $1.size }

            return (sorted, total)
        }.value

        cachedStorageByVolume = result.0
        cachedTotalStorage = result.1
        isLoadingStorage = false
    }

    // MARK: - Storage Stats

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Project Stats

/// All derived statistics for the projects list, computed in a single pass
/// so the view body only reads precomputed values.
private nonisolated struct ProjectStats: Sendable {
    var averageBPM = "-"
    var totalDuration = "0m"
    var statusData: [(status: CompletionStatus, count: Int)] = []
    var bpmDistribution: [(range: String, count: Int)] = []
    var topPlugins: [(name: String, count: Int)] = []
    var keyDistribution: [(key: String, camelot: String?, count: Int)] = []
    var projectsByMonth: [(month: Date, count: Int)] = []
    var projectsByWeek: [(week: Date, count: Int)] = []
    var projectsByDayOfWeek: [(day: String, count: Int)] = []
    var maxProjectsPerDayOfWeek = 0
    var mostProductiveDay = "-"
    var averageProjectsPerWeek = "-"

    init() {}

    init(projects: [ProjectRecord]) {
        let calendar = Calendar.current

        let bpmRanges = [
            ("< 80", 0..<80),
            ("80-99", 80..<100),
            ("100-119", 100..<120),
            ("120-139", 120..<140),
            ("140-159", 140..<160),
            ("160+", 160..<500)
        ]

        var bpmSum = 0.0
        var bpmCount = 0
        var durationTotal = 0.0
        var statusCounts: [CompletionStatus: Int] = [:]
        var bpmRangeCounts = [Int](repeating: 0, count: bpmRanges.count)
        var pluginCounts: [String: Int] = [:]
        var keyCounts: [String: Int] = [:]
        var monthCounts: [Date: Int] = [:]
        var weekCounts: [Date: Int] = [:]
        var dayCounts: [Int: Int] = [:]

        for project in projects {
            if let bpm = project.bpm {
                bpmSum += bpm
                bpmCount += 1
                let bpmInt = Int(bpm)
                if let rangeIndex = bpmRanges.firstIndex(where: { $0.1.contains(bpmInt) }) {
                    bpmRangeCounts[rangeIndex] += 1
                }
            }

            if let duration = project.duration {
                durationTotal += duration
            }

            statusCounts[project.completionStatus, default: 0] += 1

            for plugin in project.plugins {
                pluginCounts[plugin, default: 0] += 1
            }

            for key in project.musicalKeys {
                keyCounts[key, default: 0] += 1
            }

            let date = project.createdDate ?? project.filesystemModifiedDate
            if let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) {
                monthCounts[monthStart, default: 0] += 1
            }
            if let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) {
                weekCounts[weekStart, default: 0] += 1
            }
            dayCounts[calendar.component(.weekday, from: date), default: 0] += 1
        }

        if bpmCount > 0 {
            averageBPM = String(format: "%.0f", bpmSum / Double(bpmCount))
        }

        let hours = Int(durationTotal) / 3600
        let minutes = (Int(durationTotal) % 3600) / 60
        totalDuration = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"

        statusData = CompletionStatus.allCases.map { (status: $0, count: statusCounts[$0] ?? 0) }

        bpmDistribution = zip(bpmRanges, bpmRangeCounts).map { range, count in
            (range: range.0, count: count)
        }

        topPlugins = pluginCounts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        keyDistribution = keyCounts
            .map { (key: $0.key, camelot: CamelotConverter.toCamelot($0.key), count: $0.value) }
            .sorted { $0.count > $1.count }

        projectsByMonth = monthCounts
            .map { (month: $0.key, count: $0.value) }
            .sorted { $0.month < $1.month }
            .suffix(12)
            .map { $0 }

        projectsByWeek = weekCounts
            .map { (week: $0.key, count: $0.value) }
            .sorted { $0.week < $1.week }
            .suffix(24)
            .map { $0 }

        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        projectsByDayOfWeek = (1...7).map { (day: dayNames[$0], count: dayCounts[$0] ?? 0) }
        maxProjectsPerDayOfWeek = projectsByDayOfWeek.map(\.count).max() ?? 0
        mostProductiveDay = projectsByDayOfWeek.max(by: { $0.count < $1.count })?.day ?? "-"

        if !projectsByWeek.isEmpty {
            let weekTotal = projectsByWeek.reduce(0) { $0 + $1.count }
            averageProjectsPerWeek = String(format: "%.1f", Double(weekTotal) / Double(projectsByWeek.count))
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var action: (() -> Void)? = nil
    @Environment(\.theme) private var theme

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
        .themedCard(cornerRadius: 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Stat Mini Card

struct StatMiniCard: View {
    let title: String
    let value: String
    let icon: String
    @Environment(\.theme) private var theme

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
        .themedCard(cornerRadius: 8)
    }
}
