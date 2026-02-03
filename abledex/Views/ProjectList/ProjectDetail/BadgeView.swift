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
            .themedBadge(.accent)
    }
}

#Preview {
    BadgeView(label: "Test", icon: "clock")
}
