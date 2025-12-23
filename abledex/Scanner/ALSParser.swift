//
//  ALSParser.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import Foundation
import Compression

struct ParsedProjectData: Sendable {
    var bpm: Double?
    var timeSignatureNumerator: Int?
    var timeSignatureDenominator: Int?
    var audioTrackCount: Int = 0
    var midiTrackCount: Int = 0
    var returnTrackCount: Int = 0
    var abletonVersion: String?
    var abletonMinorVersion: String?
    var duration: Double?
    var samplePaths: [String] = []
    var plugins: [String] = []
    var musicalKeys: [String] = []

    nonisolated init(
        bpm: Double? = nil,
        timeSignatureNumerator: Int? = nil,
        timeSignatureDenominator: Int? = nil,
        audioTrackCount: Int = 0,
        midiTrackCount: Int = 0,
        returnTrackCount: Int = 0,
        abletonVersion: String? = nil,
        abletonMinorVersion: String? = nil,
        duration: Double? = nil,
        samplePaths: [String] = [],
        plugins: [String] = [],
        musicalKeys: [String] = []
    ) {
        self.bpm = bpm
        self.timeSignatureNumerator = timeSignatureNumerator
        self.timeSignatureDenominator = timeSignatureDenominator
        self.audioTrackCount = audioTrackCount
        self.midiTrackCount = midiTrackCount
        self.returnTrackCount = returnTrackCount
        self.abletonVersion = abletonVersion
        self.abletonMinorVersion = abletonMinorVersion
        self.duration = duration
        self.samplePaths = samplePaths
        self.plugins = plugins
        self.musicalKeys = musicalKeys
    }
}

enum ALSParserError: Error, LocalizedError {
    case fileNotFound
    case decompressionFailed
    case invalidXML
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "ALS file not found"
        case .decompressionFailed:
            return "Failed to decompress ALS file"
        case .invalidXML:
            return "ALS file does not contain valid XML"
        case .parsingFailed(let message):
            return "Failed to parse ALS file: \(message)"
        }
    }
}

struct ALSParser: Sendable {
    nonisolated init() {}

    nonisolated func parse(alsFilePath: URL) throws -> ParsedProjectData {
        guard FileManager.default.fileExists(atPath: alsFilePath.path) else {
            throw ALSParserError.fileNotFound
        }

        let compressedData = try Data(contentsOf: alsFilePath)
        let xmlData = try decompressGzip(data: compressedData)

        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            throw ALSParserError.invalidXML
        }

        return parseXML(xmlString)
    }

    private nonisolated func decompressGzip(data: Data) throws -> Data {
        guard data.count > 10 else {
            throw ALSParserError.decompressionFailed
        }

        // Check for gzip magic number
        guard data[0] == 0x1f && data[1] == 0x8b else {
            // Not gzipped - might be raw XML
            return data
        }

        // Skip gzip header and decompress
        var headerLength = 10
        let bytes = [UInt8](data)

        if bytes[3] & 0x04 != 0 {
            if data.count > headerLength + 2 {
                let extraLength = Int(bytes[headerLength]) + Int(bytes[headerLength + 1]) * 256
                headerLength += 2 + extraLength
            }
        }

        if bytes[3] & 0x08 != 0 {
            while headerLength < data.count && bytes[headerLength] != 0 {
                headerLength += 1
            }
            headerLength += 1
        }

        if bytes[3] & 0x10 != 0 {
            while headerLength < data.count && bytes[headerLength] != 0 {
                headerLength += 1
            }
            headerLength += 1
        }

        if bytes[3] & 0x02 != 0 {
            headerLength += 2
        }

        guard headerLength < data.count - 8 else {
            throw ALSParserError.decompressionFailed
        }

        let deflateData = data.subdata(in: headerLength..<(data.count - 8))
        let destinationBufferSize = min(data.count * 30, 100_000_000) // Cap at 100MB
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

        let decompressedSize = deflateData.withUnsafeBytes { sourceBuffer in
            compression_decode_buffer(
                &destinationBuffer,
                destinationBufferSize,
                sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                deflateData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            throw ALSParserError.decompressionFailed
        }

        return Data(destinationBuffer.prefix(decompressedSize))
    }

    private nonisolated func parseXML(_ xmlString: String) -> ParsedProjectData {
        var result = ParsedProjectData()

        // Parse Ableton version - look in first 2000 chars for efficiency
        let headerSection = String(xmlString.prefix(2000))

        if let range = headerSection.range(of: #"Creator="Ableton Live ([^"]+)""#, options: .regularExpression) {
            let match = headerSection[range]
            if let versionRange = match.range(of: #"(?<=Creator="Ableton Live )[^"]+"#, options: .regularExpression) {
                result.abletonVersion = String(match[versionRange])
            }
        }

        // Parse BPM - extract from Tempo block
        result.bpm = extractBPM(from: xmlString)

        // Parse time signature
        result.timeSignatureNumerator = extractFirstInt(from: xmlString, pattern: #"<TimeSignature>[^<]*<[^>]*Numerator Value="(\d+)""#) ?? 4
        result.timeSignatureDenominator = extractFirstInt(from: xmlString, pattern: #"<TimeSignature>[^<]*<[^>]*Denominator Value="(\d+)""#) ?? 4

        // Count tracks - use simple string counting for speed
        result.audioTrackCount = xmlString.components(separatedBy: "<AudioTrack Id=").count - 1
        result.midiTrackCount = xmlString.components(separatedBy: "<MidiTrack Id=").count - 1
        result.returnTrackCount = xmlString.components(separatedBy: "<ReturnTrack Id=").count - 1

        // Parse arrangement length
        if let beats = extractFirstDouble(from: xmlString, pattern: #"<CurrentEnd Value="([\d.]+)""#),
           let bpm = result.bpm, bpm > 0 {
            result.duration = (beats / bpm) * 60.0
        }

        // Extract plugins (limit search to avoid memory issues)
        result.plugins = extractPlugins(from: xmlString)

        // Extract sample count (not full paths to save memory)
        result.samplePaths = extractSampleNames(from: xmlString)

        // Extract musical keys from scale information
        result.musicalKeys = extractMusicalKeys(from: xmlString)

        return result
    }

    private nonisolated func extractBPM(from xmlString: String) -> Double? {
        // Find the Tempo block and extract the Manual value
        // The structure is: <Tempo>...<Manual Value="120" />...</Tempo>
        guard let tempoStart = xmlString.range(of: "<Tempo>"),
              let tempoEnd = xmlString.range(of: "</Tempo>", range: tempoStart.upperBound..<xmlString.endIndex) else {
            return nil
        }

        let tempoBlock = String(xmlString[tempoStart.lowerBound..<tempoEnd.upperBound])

        // Look for <Manual Value="XXX" /> within the Tempo block
        let pattern = #"<Manual Value="([\d.]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(tempoBlock.startIndex..., in: tempoBlock)
        guard let match = regex.firstMatch(in: tempoBlock, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: tempoBlock) else {
            return nil
        }

        return Double(tempoBlock[valueRange])
    }

    private nonisolated func extractFirstDouble(from string: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return Double(string[valueRange])
    }

    private nonisolated func extractFirstInt(from string: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return Int(string[valueRange])
    }

    private nonisolated func extractSampleNames(from xmlString: String) -> [String] {
        var names: Set<String> = []

        // Only look for sample file names, not full paths
        let pattern = #"<Name Value="([^"]+\.(wav|aif|aiff|mp3|flac|m4a))""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let range = NSRange(xmlString.startIndex..., in: xmlString)
        let matches = regex.matches(in: xmlString, options: [], range: range)

        for match in matches.prefix(500) { // Limit to first 500 samples
            if let valueRange = Range(match.range(at: 1), in: xmlString) {
                names.insert(String(xmlString[valueRange]))
            }
        }

        return Array(names).sorted()
    }

    private nonisolated func extractPlugins(from xmlString: String) -> [String] {
        var plugins: Set<String> = []

        let pattern = #"<PlugName Value="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(xmlString.startIndex..., in: xmlString)
        let matches = regex.matches(in: xmlString, options: [], range: range)

        for match in matches.prefix(200) { // Limit
            if let valueRange = Range(match.range(at: 1), in: xmlString) {
                let name = String(xmlString[valueRange])
                if !name.isEmpty && name != "None" && !isBuiltInDevice(name) {
                    plugins.insert(name)
                }
            }
        }

        return Array(plugins).sorted()
    }

    private nonisolated func isBuiltInDevice(_ name: String) -> Bool {
        let prefixes = ["Ableton", "Audio", "Auto", "Beat", "Corpus", "Delay", "Drum", "EQ", "External", "Filter", "Flanger", "Gate", "Glue", "Grain", "Limiter", "Looper", "MIDI", "Multiband", "Overdrive", "Pedal", "Phaser", "Pitch", "Redux", "Resonator", "Reverb", "Saturator", "Scale", "Simple", "Spectrum", "Tension", "Tuner", "Utility", "Vinyl", "Vocoder", "Wavetable"]
        return prefixes.contains { name.hasPrefix($0) }
    }

    private nonisolated func extractMusicalKeys(from xmlString: String) -> [String] {
        var keys: Set<String> = []

        // Pattern to match ScaleInformation blocks with Root and Name values
        // Structure: <ScaleInformation><Root Value="X" /><Name Value="Y" /></ScaleInformation>
        let pattern = #"<ScaleInformation>\s*<Root Value="(\d+)"\s*/>\s*<Name Value="(\d+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(xmlString.startIndex..., in: xmlString)
        let matches = regex.matches(in: xmlString, options: [], range: range)

        for match in matches.prefix(100) { // Limit to avoid performance issues
            guard match.numberOfRanges >= 3,
                  let rootRange = Range(match.range(at: 1), in: xmlString),
                  let nameRange = Range(match.range(at: 2), in: xmlString),
                  let root = Int(xmlString[rootRange]),
                  let scaleName = Int(xmlString[nameRange]) else {
                continue
            }

            if let keyString = formatMusicalKey(root: root, scaleName: scaleName) {
                keys.insert(keyString)
            }
        }

        return Array(keys).sorted()
    }

    private nonisolated func formatMusicalKey(root: Int, scaleName: Int) -> String? {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let scaleNames = [
            "Major", "Minor", "Dorian", "Mixolydian", "Lydian", "Phrygian", "Locrian",
            "Whole Tone", "Half-Whole Dim", "Whole-Half Dim", "Minor Blues",
            "Minor Pentatonic", "Major Pentatonic", "Harmonic Minor", "Melodic Minor",
            "Super Locrian", "Bhairav", "Hungarian Minor", "Minor Gypsy", "Hirajoshi",
            "In-Sen", "Iwato", "Kumoi", "Pelog", "Spanish"
        ]

        guard root >= 0 && root < noteNames.count else { return nil }
        guard scaleName >= 0 && scaleName < scaleNames.count else { return nil }

        return "\(noteNames[root]) \(scaleNames[scaleName])"
    }
}
