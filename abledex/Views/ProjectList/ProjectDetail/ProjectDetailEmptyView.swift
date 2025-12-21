//
//  ProjectDetailEmptyView.swift
//  abledex
//
//  Created by Brett Henderson on 12/21/25.
//

import SwiftUI

struct ProjectDetailEmptyView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Project Selected", systemImage: "music.note")
        } description: {
            Text("Select a project from the list to view its details.")
        }
    }
}

#Preview {
    ProjectDetailEmptyView()
}
