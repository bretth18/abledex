//
//  WaveformView.swift
//  abledex
//
//  Created by Brett Henderson on 12/23/25.
//

import SwiftUI
import AVFoundation
import Accelerate

// MARK: - Waveform Data Extractor

actor WaveformDataCache {
    static let shared = WaveformDataCache()
    private var cache: [URL: [Float]] = [:]

    func get(_ url: URL) -> [Float]? {
        cache[url]
    }

    func set(_ url: URL, data: [Float]) {
        cache[url] = data
        // Limit cache size to 50 entries
        if cache.count > 50 {
            cache.removeValue(forKey: cache.keys.first!)
        }
    }
}

enum WaveformExtractor {
    /// Extract waveform data from an audio file
    /// - Parameters:
    ///   - url: The audio file URL
    ///   - sampleCount: Number of samples to return (default 150 for efficient rendering)
    /// - Returns: Array of normalized amplitudes (0.0 to 1.0)
    static func extractWaveform(from url: URL, sampleCount: Int = 150) async -> [Float] {
        // Check cache first
        if let cached = await WaveformDataCache.shared.get(url) {
            return cached
        }

        // Extract waveform data
        let waveform = await Task.detached(priority: .utility) {
            extractWaveformSync(from: url, sampleCount: sampleCount)
        }.value

        // Cache the result
        await WaveformDataCache.shared.set(url, data: waveform)

        return waveform
    }

    private static func extractWaveformSync(from url: URL, sampleCount: Int) -> [Float] {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return Array(repeating: 0.5, count: sampleCount)
        }

        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return Array(repeating: 0.5, count: sampleCount)
        }

        do {
            try audioFile.read(into: buffer)
        } catch {
            return Array(repeating: 0.5, count: sampleCount)
        }

        guard let channelData = buffer.floatChannelData else {
            return Array(repeating: 0.5, count: sampleCount)
        }

        let channelCount = Int(format.channelCount)
        let totalFrames = Int(buffer.frameLength)

        // Calculate samples per bucket
        let framesPerSample = max(1, totalFrames / sampleCount)

        var waveform: [Float] = []
        waveform.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let startFrame = i * framesPerSample
            let endFrame = min(startFrame + framesPerSample, totalFrames)
            let frameRange = endFrame - startFrame

            guard frameRange > 0 else {
                waveform.append(0)
                continue
            }

            var maxAmplitude: Float = 0

            // Find peak amplitude across all channels using Accelerate
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                var channelMax: Float = 0
                vDSP_maxmgv(samples + startFrame, 1, &channelMax, vDSP_Length(frameRange))
                maxAmplitude = max(maxAmplitude, channelMax)
            }

            waveform.append(maxAmplitude)
        }

        // Normalize to 0-1 range
        var globalMax: Float = 0
        vDSP_maxv(waveform, 1, &globalMax, vDSP_Length(waveform.count))

        if globalMax > 0 {
            var scale = 1.0 / globalMax
            vDSP_vsmul(waveform, 1, &scale, &waveform, 1, vDSP_Length(waveform.count))
        }

        return waveform
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let waveformData: [Float]
    let progress: Double // 0.0 to 1.0
    let isActive: Bool
    let onSeek: ((Double) -> Void)?

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var displayProgress: Double {
        isDragging ? dragProgress : progress
    }

    init(
        waveformData: [Float],
        progress: Double = 0,
        isActive: Bool = false,
        onSeek: ((Double) -> Void)? = nil
    ) {
        self.waveformData = waveformData
        self.progress = progress
        self.isActive = isActive
        self.onSeek = onSeek
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawWaveform(context: context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard onSeek != nil else { return }
                        isDragging = true
                        dragProgress = max(0, min(1, value.location.x / geometry.size.width))
                    }
                    .onEnded { value in
                        guard let onSeek else { return }
                        let fraction = max(0, min(1, value.location.x / geometry.size.width))
                        onSeek(fraction)
                        isDragging = false
                    }
            )
        }
        .frame(height: 32)
    }

    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        let barCount = waveformData.count
        guard barCount > 0 else { return }

        let barWidth = size.width / CGFloat(barCount)
        let barSpacing: CGFloat = 1
        let actualBarWidth = max(1, barWidth - barSpacing)
        let centerY = size.height / 2

        let progressIndex = Int(displayProgress * Double(barCount))

        for (index, amplitude) in waveformData.enumerated() {
            let x = CGFloat(index) * barWidth + barSpacing / 2
            let barHeight = max(2, CGFloat(amplitude) * size.height * 0.9)

            let rect = CGRect(
                x: x,
                y: centerY - barHeight / 2,
                width: actualBarWidth,
                height: barHeight
            )

            let color: Color
            if index < progressIndex {
                color = isActive ? .accentColor : .gray.opacity(0.6)
            } else {
                color = .gray.opacity(0.3)
            }

            context.fill(
                RoundedRectangle(cornerRadius: actualBarWidth / 2)
                    .path(in: rect),
                with: .color(color)
            )
        }

        // Draw playhead line
        if isActive || isDragging {
            let playheadX = size.width * displayProgress
            var playheadPath = Path()
            playheadPath.move(to: CGPoint(x: playheadX, y: 0))
            playheadPath.addLine(to: CGPoint(x: playheadX, y: size.height))
            context.stroke(playheadPath, with: .color(.accentColor), lineWidth: 2)
        }
    }
}

// MARK: - Async Waveform View

struct AsyncWaveformView: View {
    let url: URL
    let progress: Double
    let duration: Double
    let isActive: Bool
    let onSeek: (Double) -> Void

    @State private var waveformData: [Float] = []
    @State private var isLoading = true

    private var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return progress / duration
    }

    var body: some View {
        Group {
            if isLoading {
                // Show placeholder while loading
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 32)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            } else {
                WaveformView(
                    waveformData: waveformData,
                    progress: progressFraction,
                    isActive: isActive
                ) { fraction in
                    let seekTime = fraction * duration
                    onSeek(seekTime)
                }
            }
        }
        .task(id: url) {
            isLoading = true
            waveformData = await WaveformExtractor.extractWaveform(from: url)
            isLoading = false
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Static waveform
        WaveformView(
            waveformData: (0..<100).map { _ in Float.random(in: 0.2...1.0) },
            progress: 0.3,
            isActive: true
        )

        // Inactive waveform
        WaveformView(
            waveformData: (0..<100).map { _ in Float.random(in: 0.2...1.0) },
            progress: 0.5,
            isActive: false
        )
    }
    .padding()
    .frame(width: 300)
}
