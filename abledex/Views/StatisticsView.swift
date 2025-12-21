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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Stats")
                    .font(.largeTitle.bold())
                    .padding(.bottom, 8)

                // Overview cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(title: "Total Projects", value: "\(appState.projectCount)", icon: "music.note.list", color: .blue)
                    StatCard(title: "Favorites", value: "\(appState.favoritesCount)", icon: "star.fill", color: .yellow)
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

                        // Legend
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(statusData, id: \.status) { item in
                                HStack {
                                    Circle()
                                        .fill(item.color)
                                        .frame(width: 12, height: 12)
                                    Text(item.status.label)
                                    Spacer()
                                    Text("\(item.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(width: 200)
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
                        // Fallback for older macOS
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

                // Top plugins
                VStack(alignment: .leading, spacing: 12) {
                    Text("Most Used Plugins")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(topPlugins.prefix(10), id: \.name) { plugin in
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
                            .foregroundStyle(.green.gradient)
                        }
                        .frame(height: 200)
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
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
            .suffix(12) // Last 12 months
            .map { $0 }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
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
    }
}
