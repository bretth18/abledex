//
//  BatchTagSheetView.swift
//  abledex
//
//  Created by Brett Henderson on 4/4/26.
//

import SwiftUI

/// Sheet for adding a tag to multiple selected projects.
struct BatchTagSheetView: View {
    let selectedCount: Int
    @Binding var tagInput: String
    @Binding var isPresented: Bool
    let onAdd: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Tag to \(selectedCount) Projects")
                .font(.headline)

            TextField("Tag name", text: $tagInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            HStack {
                Button("Cancel") {
                    tagInput = ""
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    let tag = tagInput.trimmingCharacters(in: .whitespaces)
                    if !tag.isEmpty {
                        onAdd(tag)
                        tagInput = ""
                        isPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
