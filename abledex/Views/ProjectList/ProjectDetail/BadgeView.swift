//
//  BadgeView.swift
//  abledex
//
//  Created by Brett Henderson on 12/21/25.
//

import SwiftUI

struct BadgeView: View {
    let label: String
    let icon: String

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.tint.opacity(0.1))
            .foregroundStyle(.tint)
            .clipShape(Capsule())
    }
}

#Preview {
    BadgeView(label: "Test", icon: "clock")
}
