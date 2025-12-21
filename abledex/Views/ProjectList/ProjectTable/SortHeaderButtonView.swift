//
//  SortHeaderButtonView.swift
//  abledex
//
//  Created by Brett Henderson on 12/21/25.
//

import SwiftUI

struct SortHeaderButtonView: View {
    let title: String
    let column: SortColumn
    @Binding var currentColumn: SortColumn
    @Binding var ascending: Bool

    var body: some View {
        Button {
            if currentColumn == column {
                ascending.toggle()
            } else {
                currentColumn = column
                ascending = column == .name
            }
        } label: {
            HStack {
                Text(title)
                if currentColumn == column {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SortHeaderButtonView(title: "Name", column: .name, currentColumn: .constant(.name), ascending: .constant(true))
}
