//
//  SidebarFilterSection.swift
//  abledex
//

import SwiftUI

/// How one value renders as a sidebar row.
struct SidebarFilterRow {
    var title: String
    var icon: String
    var tint: Color?

    init(_ title: String, icon: String, tint: Color? = nil) {
        self.title = title
        self.icon = icon
        self.tint = tint
    }
}

/// A collapsible sidebar section whose rows toggle one mutually exclusive
/// filter on AppState. Rows show a project count and highlight when active.
struct SidebarFilterSection<Value: Hashable>: View {
    let title: String
    let section: SidebarSection
    let values: [Value]
    let filter: ReferenceWritableKeyPath<AppState, Value?>
    let count: (Value) -> Int
    let row: (Value) -> SidebarFilterRow

    /// Rows shown before collapsing the rest into a "+ n more" line.
    var visibleLimit: Int?
    /// Drops values with no matching projects (used by the color section).
    var hidesEmpty = false

    @Binding var expandedSections: Set<SidebarSection>
    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme

    private var shownValues: [Value] {
        let candidates = hidesEmpty ? values.filter { count($0) > 0 } : values
        guard let visibleLimit else { return candidates }
        return Array(candidates.prefix(visibleLimit))
    }

    private var hiddenCount: Int {
        let total = hidesEmpty ? values.filter { count($0) > 0 }.count : values.count
        return max(0, total - shownValues.count)
    }

    var body: some View {
        if !shownValues.isEmpty {
            Section(isExpanded: expansionBinding) {
                ForEach(shownValues, id: \.self) { value in
                    let descriptor = row(value)
                    Button {
                        appState.toggleSectionFilter(filter, value)
                    } label: {
                        Label {
                            HStack {
                                Text(descriptor.title)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(count(value))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: descriptor.icon)
                                .foregroundStyle(descriptor.tint ?? .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        appState[keyPath: filter] == value ? theme.surfaceSelected : Color.clear
                    )
                }

                if hiddenCount > 0 {
                    Text("+ \(hiddenCount) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(title)
            }
        }
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }
}
