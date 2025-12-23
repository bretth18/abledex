//
//  WaveformService.swift
//  abledex
//
//  Created by Brett Henderson on 12/23/25.
//

import Foundation
import AVFoundation
import Accelerate

// MARK: - Waveform Data Cache

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

// MARK: - Waveform Extractor

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

    private nonisolated static func extractWaveformSync(from url: URL, sampleCount: Int) -> [Float] {
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
