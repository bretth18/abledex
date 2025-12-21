//
//  AudioScrubberView.swift
//  abledex
//
//  Created by Brett Henderson on 12/21/25.
//

import SwiftUI

struct AudioScrubberView: View {
    let progress: Double
    let duration: Double
    let isActive: Bool
    let onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var displayProgress: Double {
        isDragging ? dragProgress : progress
    }

    private var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return displayProgress / duration
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)

                // Progress fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? Color.accentColor : Color.gray.opacity(0.5))
                    .frame(width: max(0, geometry.size.width * progressFraction), height: 4)

                // Thumb (only show when active or dragging)
                if isActive || isDragging {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, min(geometry.size.width - 10, geometry.size.width * progressFraction - 5)))
                }
            }
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let fraction = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = fraction * duration
                    }
                    .onEnded { value in
                        let fraction = max(0, min(1, value.location.x / geometry.size.width))
                        let seekTime = fraction * duration
                        onSeek(seekTime)
                        isDragging = false
                    }
            )
        }
        .frame(height: 10)
    }
}

#Preview {
    AudioScrubberView(progress: 50.0, duration: 120.0, isActive: true) { newTime in
        print("Seek to \(newTime)")
    }
}
