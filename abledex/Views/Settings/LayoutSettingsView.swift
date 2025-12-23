//
//  LayoutSettingsView.swift
//  abledex
//
//  Created by Brett Henderson on 12/23/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct LayoutSettingsView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Sidebar").tag(0)
                Text("Detail View").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            if selectedTab == 0 {
                SidebarOrderView()
            } else {
                DetailOrderView()
            }
        }
    }
}

// MARK: - Sidebar Order View

struct SidebarOrderView: View {
    @State private var sections: [SidebarSection] = SidebarOrderStorage.order
    @State private var draggedSection: SidebarSection?

    var body: some View {
        Form {
            Section {
                Text("Drag to reorder sidebar sections. The Library section always appears first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List {
                    ForEach(sections) { section in
                        reorderableRow(section: section)
                    }
                }
                .listStyle(.plain)
                .frame(height: 260)
            } header: {
                Text("Section Order")
            }

            Section {
                Button("Reset to Default") {
                    withAnimation {
                        SidebarOrderStorage.reset()
                        sections = SidebarSection.defaultOrder
                    }
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
        .onChange(of: sections) { _, newValue in
            SidebarOrderStorage.order = newValue
        }
    }

    @ViewBuilder
    private func reorderableRow(section: SidebarSection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.caption)

            Image(systemName: section.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(section.rawValue)

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(draggedSection == section ? 0.5 : 1)
        .onDrag {
            draggedSection = section
            return NSItemProvider(object: section.rawValue as NSString)
        }
        .onDrop(of: [.text], delegate: GenericDropDelegate(
            item: section,
            items: $sections,
            draggedItem: $draggedSection
        ))
    }
}

// MARK: - Detail Order View

struct DetailOrderView: View {
    @State private var sections: [DetailSection] = DetailOrderStorage.order
    @State private var draggedSection: DetailSection?

    var body: some View {
        Form {
            Section {
                Text("Drag to reorder detail view sections. The header always appears first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List {
                    ForEach(sections) { section in
                        reorderableRow(section: section)
                    }
                }
                .listStyle(.plain)
                .frame(height: 260)
            } header: {
                Text("Section Order")
            }

            Section {
                Button("Reset to Default") {
                    withAnimation {
                        DetailOrderStorage.reset()
                        sections = DetailSection.defaultOrder
                    }
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
        .onChange(of: sections) { _, newValue in
            DetailOrderStorage.order = newValue
        }
    }

    @ViewBuilder
    private func reorderableRow(section: DetailSection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.caption)

            Image(systemName: section.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(section.rawValue)

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(draggedSection == section ? 0.5 : 1)
        .onDrag {
            draggedSection = section
            return NSItemProvider(object: section.rawValue as NSString)
        }
        .onDrop(of: [.text], delegate: GenericDropDelegate(
            item: section,
            items: $sections,
            draggedItem: $draggedSection
        ))
    }
}

// MARK: - Generic Drop Delegate

struct GenericDropDelegate<T: Equatable>: DropDelegate {
    let item: T
    @Binding var items: [T]
    @Binding var draggedItem: T?

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem,
              draggedItem != item,
              let fromIndex = items.firstIndex(of: draggedItem),
              let toIndex = items.firstIndex(of: item) else {
            return
        }

        withAnimation(.default) {
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

#Preview {
    LayoutSettingsView()
        .frame(width: 500, height: 450)
}
