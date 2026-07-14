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

    private struct Entry {
        var data: [Float]
        var generation: UInt64
    }

    private var cache: [URL: Entry] = [:]
    private var inFlight: [URL: Task<[Float], Never>] = [:]
    private var generation: UInt64 = 0
    private let maxEntries = 50

    /// Return the cached waveform for a URL, extracting it if needed.
    /// Concurrent requests for the same URL share a single extraction task.
    func waveform(for url: URL, sampleCount: Int) async -> [Float] {
        if var entry = cache[url] {
            // Refresh recency for true LRU eviction
            generation += 1
            entry.generation = generation
            cache[url] = entry
            return entry.data
        }

        // Join an in-flight extraction instead of starting a duplicate
        if let task = inFlight[url] {
            return await task.value
        }

        let task = Task.detached(priority: .utility) {
            WaveformExtractor.extractWaveformSync(from: url, sampleCount: sampleCount)
        }
        inFlight[url] = task

        let waveform = await task.value
        inFlight[url] = nil
        insert(url, data: waveform)

        return waveform
    }

    private func insert(_ url: URL, data: [Float]) {
        generation += 1
        cache[url] = Entry(data: data, generation: generation)

        // Limit cache size by evicting the least recently used entry
        if cache.count > maxEntries,
           let oldest = cache.min(by: { $0.value.generation < $1.value.generation }) {
            cache.removeValue(forKey: oldest.key)
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
        await WaveformDataCache.shared.waveform(for: url, sampleCount: sampleCount)
    }

    fileprivate nonisolated static func extractWaveformSync(from url: URL, sampleCount: Int) -> [Float] {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return Array(repeating: 0.5, count: sampleCount)
        }

        let format = audioFile.processingFormat
        let totalFrames = Int(audioFile.length)

        // Read in fixed-size chunks so memory stays bounded regardless of file length
        let chunkCapacity: AVAudioFrameCount = 1 << 20

        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkCapacity) else {
            return Array(repeating: 0.5, count: sampleCount)
        }

        let channelCount = Int(format.channelCount)
        let framesPerBucket = max(1, totalFrames / sampleCount)

        var waveform = [Float](repeating: 0, count: sampleCount)
        var framesRead = 0

        while framesRead < totalFrames {
            do {
                try audioFile.read(into: buffer, frameCount: chunkCapacity)
            } catch {
                return Array(repeating: 0.5, count: sampleCount)
            }

            let chunkFrames = Int(buffer.frameLength)
            guard chunkFrames > 0 else { break }

            guard let channelData = buffer.floatChannelData else {
                return Array(repeating: 0.5, count: sampleCount)
            }

            // Fold this chunk's peaks into the buckets it overlaps
            var offset = 0
            while offset < chunkFrames {
                let globalFrame = framesRead + offset
                let bucket = min(globalFrame / framesPerBucket, sampleCount - 1)

                // The last bucket absorbs any trailing frames left over by integer division
                let bucketEnd = bucket == sampleCount - 1
                    ? totalFrames
                    : (bucket + 1) * framesPerBucket
                var frameRange = min(chunkFrames - offset, bucketEnd - globalFrame)
                if frameRange <= 0 {
                    // Decoder yielded more frames than AVAudioFile.length estimated
                    // (VBR/corrupt files) — fold the remainder into the last bucket
                    // instead of spinning forever or passing a negative count to vDSP.
                    frameRange = chunkFrames - offset
                }

                var maxAmplitude = waveform[bucket]

                // Find peak amplitude across all channels using Accelerate
                for channel in 0..<channelCount {
                    let samples = channelData[channel]
                    var channelMax: Float = 0
                    vDSP_maxmgv(samples + offset, 1, &channelMax, vDSP_Length(frameRange))
                    maxAmplitude = max(maxAmplitude, channelMax)
                }

                waveform[bucket] = maxAmplitude
                offset += frameRange
            }

            framesRead += chunkFrames
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
