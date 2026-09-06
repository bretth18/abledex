//
//  ScanProgressView.swift
//  abledex
//

import SwiftUI

/// Live scan status shown above the sidebar's scan button.
struct ScanProgressView: View {
    let progress: ScanProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch progress {
            case .starting:
                busy("Preparing scan...")

            case .discovering(let location):
                busy("Finding projects in \(location)...")

            case .parsing(let current, let total, let name):
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    ProgressView(value: Double(current), total: Double(total))
                        .animation(.easeInOut(duration: 0.2), value: current)
                    HStack {
                        Text("\(current) of \(total) projects")
                        Spacer()
                        Text("\(Int((Double(current) / Double(total)) * 100))%")
                            .fontWeight(.medium)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

            case .completed(let count, let duration):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Found \(count) projects in \(String(format: "%.1f", duration))s")
                        .font(.caption)
                }

            case .failed(let error):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal)
    }

    private func busy(_ message: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
            Text(message)
                .font(.caption)
                .lineLimit(1)
        }
    }
}
