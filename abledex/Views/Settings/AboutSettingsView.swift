//
//  AboutSettingsView.swift
//  abledex
//
//  Created by Brett Henderson on 12/21/25.
//

import SwiftUI

struct AboutSettingsView: View {
    
    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 4) {
                    Text("abledex")
                        .font(.largeTitle.bold())
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("© 2025 COMPUTER DATA")
                }
            } header: {
                Text("About")
            }
            
            Section {
                Link("License (MIT)", destination: URL(string: "https://github.com/bretth18/abledex/blob/main/LICENSE")!)
            } header: {
                Text("License")
            }
            
        }
        .formStyle(.grouped)
        .padding()
                
    }
}

#Preview {
    AboutSettingsView()
}
