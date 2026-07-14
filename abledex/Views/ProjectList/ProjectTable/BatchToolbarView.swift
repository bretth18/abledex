//
//  BatchToolbarView.swift
//  abledex
//
//  Created by Brett Henderson on 4/4/26.
//

import SwiftUI

/// Toolbar shown when multiple projects are selected, shared between SwiftUI and NSTableView implementations.
struct BatchToolbarView: View {
    let selectedCount: Int
    @Binding var showDeleteConfirmation: Bool
    @Binding var showBatchTagSheet: Bool
    let onSetStatus: (CompletionStatus) -> Void
    let onFavoriteAll: () -> Void
    let onUnfavoriteAll: () -> Void
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 16) {
            Text("\(selectedCount) selected")
                .font(.headline)

            Divider()
                .frame(height: 20)

            Menu {
                ForEach(CompletionStatus.allCases, id: \.self) { status in
                    Button(action: { onSetStatus(status) }) {
                        Label(status.label, systemImage: status.icon)
                    }
                }
            } label: {
                Label("Set Status", systemImage: "checkmark.circle")
            }
            .menuStyle(.borderlessButton)

            Button(action: { showBatchTagSheet = true }) {
                Label("Add Tag", systemImage: "tag")
            }
            .buttonStyle(.borderless)

            Button(action: onFavoriteAll) {
                Label("Favorite All", systemImage: "star.fill")
            }
            .buttonStyle(.borderless)

            Button(action: onUnfavoriteAll) {
                Label("Unfavorite All", systemImage: "star.slash")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(theme.usesCustomBackground ? AnyShapeStyle(theme.barBackground) : AnyShapeStyle(.bar))
    }
}
