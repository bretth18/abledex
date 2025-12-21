//
//  AudioPreviewService.swift
//  abledex
//
//  Created by Brett Henderson on 12/16/25.
//

import Foundation
import AVFoundation

@MainActor
@Observable
final class AudioPreviewService {
    private var audioPlayer: AVAudioPlayer?

    var isPlaying: Bool = false
    var currentlyPlayingURL: URL?
    var playbackProgress: Double = 0
    var duration: Double = 0

    private var progressTimer: Timer?

    nonisolated init() {}

    struct PreviewableAudio: Identifiable, Sendable {
        let id = UUID()
        let url: URL
        let name: String
        let duration: TimeInterval?
        let isRecorded: Bool // True if in Samples/Recorded folder

        var formattedDuration: String? {
            guard let duration else { return nil }
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    nonisolated func findPreviewableAudio(in projectFolderPath: String) -> [PreviewableAudio] {
        let projectURL = URL(fileURLWithPath: projectFolderPath)
        let fileManager = FileManager.default
        var audioFiles: [PreviewableAudio] = []

        let supportedExtensions = ["wav", "aif", "aiff", "mp3", "m4a", "flac"]

        // Priority 1: Samples/Recorded folder (user's own recordings)
        let recordedFolder = projectURL.appendingPathComponent("Samples/Recorded")
        if let recordedFiles = try? fileManager.contentsOfDirectory(at: recordedFolder, includingPropertiesForKeys: nil) {
            for fileURL in recordedFiles {
                if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    let duration = getAudioDuration(url: fileURL)
                    audioFiles.append(PreviewableAudio(
                        url: fileURL,
                        name: fileURL.lastPathComponent,
                        duration: duration,
                        isRecorded: true
                    ))
                }
            }
        }

        // Priority 2: Samples/Processed folder (bounced/frozen clips)
        let processedFolder = projectURL.appendingPathComponent("Samples/Processed")
        if let processedFiles = try? fileManager.contentsOfDirectory(at: processedFolder, includingPropertiesForKeys: [.isRegularFileKey]) {
            for fileURL in processedFiles where fileURL.hasDirectoryPath == false {
                if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    let duration = getAudioDuration(url: fileURL)
                    audioFiles.append(PreviewableAudio(
                        url: fileURL,
                        name: fileURL.lastPathComponent,
                        duration: duration,
                        isRecorded: false
                    ))
                }
            }
        }

        // Priority 3: Other Samples subfolders (imported samples)
        let samplesFolder = projectURL.appendingPathComponent("Samples")
        if let samplesSubfolders = try? fileManager.contentsOfDirectory(at: samplesFolder, includingPropertiesForKeys: [.isDirectoryKey]) {
            for subfolder in samplesSubfolders {
                // Skip already processed folders
                if subfolder.lastPathComponent == "Recorded" || subfolder.lastPathComponent == "Processed" {
                    continue
                }

                if let isDirectory = try? subfolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory {
                    if let files = try? fileManager.contentsOfDirectory(at: subfolder, includingPropertiesForKeys: nil) {
                        for fileURL in files.prefix(10) { // Limit per subfolder
                            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                                let duration = getAudioDuration(url: fileURL)
                                audioFiles.append(PreviewableAudio(
                                    url: fileURL,
                                    name: fileURL.lastPathComponent,
                                    duration: duration,
                                    isRecorded: false
                                ))
                            }
                        }
                    }
                }
            }
        }

        // Limit total results and sort (recorded first, then by name)
        return Array(audioFiles.prefix(50)).sorted { a, b in
            if a.isRecorded != b.isRecorded {
                return a.isRecorded
            }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    nonisolated private func getAudioDuration(url: URL) -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        guard duration.isValid && !duration.isIndefinite else { return nil }
        return CMTimeGetSeconds(duration)
    }
    
    private func getAudioDurationAsync(url: URL) async throws  -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.isValid && !duration.isIndefinite else { return nil }
        return CMTimeGetSeconds(duration)
    }

    func play(url: URL) {
        // Stop any currently playing audio
        stop()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            isPlaying = true
            currentlyPlayingURL = url
            duration = audioPlayer?.duration ?? 0
            playbackProgress = 0

            // Start progress timer
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateProgress()
                }
            }
        } catch {
            print("Failed to play audio: \(error)")
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        progressTimer?.invalidate()
        progressTimer = nil
        isPlaying = false
        currentlyPlayingURL = nil
        playbackProgress = 0
        duration = 0
    }

    func togglePlayPause(url: URL) {
        if currentlyPlayingURL == url && isPlaying {
            pause()
        } else if currentlyPlayingURL == url && !isPlaying {
            resume()
        } else {
            play(url: url)
        }
    }

    private func pause() {
        audioPlayer?.pause()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func resume() {
        audioPlayer?.play()
        isPlaying = true
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
        }
    }

    private func updateProgress() {
        guard let player = audioPlayer else {
            stop()
            return
        }

        if !player.isPlaying && isPlaying {
            // Playback finished
            stop()
            return
        }

        playbackProgress = player.currentTime
    }

    func seek(to time: Double) {
        audioPlayer?.currentTime = time
        playbackProgress = time
    }
}
