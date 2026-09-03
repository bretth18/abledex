//
//  MusicProjectsSection.swift
//  abledex
//

import SwiftUI

/// Sidebar section listing music projects (EPs, albums, singles), with
/// creation, renaming, and status/type editing.
struct MusicProjectsSection: View {
    @Binding var expandedSections: Set<SidebarSection>
    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme

    @State private var showNewCollectionSheet = false
    @State private var newCollectionName = ""
    @State private var newCollectionKind: CollectionKind = .ep
    @State private var collectionToRename: CollectionRecord?
    @State private var renameText = ""

    var body: some View {
        Section(isExpanded: expansionBinding) {
            ForEach(appState.collections) { collection in
                row(collection)
            }

            Button {
                newCollectionName = ""
                newCollectionKind = .ep
                showNewCollectionSheet = true
            } label: {
                Label("New Music Project...", systemImage: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Music Projects")
        }
        .sheet(isPresented: $showNewCollectionSheet) {
            newCollectionSheet
        }
        .alert(
            "Rename Music Project",
            isPresented: Binding(
                get: { collectionToRename != nil },
                set: { if !$0 { collectionToRename = nil } }
            ),
            presenting: collectionToRename
        ) { collection in
            TextField("Name", text: $renameText)
            Button("Rename") {
                var updated = collection
                updated.name = renameText.trimmingCharacters(in: .whitespaces)
                guard !updated.name.isEmpty else { return }
                save(updated, failure: "Failed to Rename Music Project")
            }
            .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ collection: CollectionRecord) -> some View {
        let progress = appState.collectionProgress(collection)
        return Button {
            appState.toggleSectionFilter(\.selectedCollectionFilter, collection.id)
        } label: {
            Label {
                HStack {
                    Text(collection.name)
                    Spacer()
                    Text("\(progress.done)/\(progress.total)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: collection.status == .released ? "checkmark.seal.fill" : collection.kind.icon)
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(
            appState.selectedCollectionFilter == collection.id ? theme.surfaceSelected : Color.clear
        )
        .contextMenu {
            Button("Rename...") {
                renameText = collection.name
                collectionToRename = collection
            }

            Menu("Set Status") {
                ForEach(CollectionStatus.allCases, id: \.self) { status in
                    Button {
                        var updated = collection
                        updated.status = status
                        save(updated, failure: "Failed to Update Music Project")
                    } label: {
                        Label(status.label, systemImage: collection.status == status ? "checkmark" : status.icon)
                    }
                }
            }

            Menu("Set Type") {
                ForEach(CollectionKind.allCases, id: \.self) { kind in
                    Button {
                        var updated = collection
                        updated.kind = kind
                        save(updated, failure: "Failed to Update Music Project")
                    } label: {
                        Label(kind.label, systemImage: collection.kind == kind ? "checkmark" : kind.icon)
                    }
                }
            }

            Divider()

            Button("Delete Music Project", role: .destructive) {
                Task {
                    do {
                        try await appState.deleteCollection(collection)
                    } catch {
                        appState.reportError("Failed to Delete Music Project", error)
                    }
                }
            }
        }
    }

    private var newCollectionSheet: some View {
        VStack(spacing: 16) {
            Text("New Music Project")
                .font(.headline)

            TextField("Name (e.g. Summer EP)", text: $newCollectionName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)

            Picker("Type", selection: $newCollectionKind) {
                ForEach(CollectionKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            HStack {
                Button("Cancel") {
                    showNewCollectionSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        do {
                            let collection = try await appState.createCollection(name: name, kind: newCollectionKind)
                            appState.selectedCollectionFilter = collection.id
                        } catch {
                            appState.reportError("Failed to Create Music Project", error)
                        }
                        showNewCollectionSheet = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func save(_ collection: CollectionRecord, failure: String) {
        Task {
            do {
                try await appState.updateCollection(collection)
            } catch {
                appState.reportError(failure, error)
            }
        }
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expandedSections.contains(.musicProjects) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(.musicProjects)
                } else {
                    expandedSections.remove(.musicProjects)
                }
            }
        )
    }
}
