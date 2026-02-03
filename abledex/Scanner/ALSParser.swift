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

// Cached regex patterns — compiled once at launch, reused across all parse calls
private enum ALSRegex {
    static let timeSignatureNumerator = try! NSRegularExpression(
        pattern: #"<TimeSignature>[^<]*<[^>]*Numerator Value="(\d+)""#
    )
    static let timeSignatureDenominator = try! NSRegularExpression(
        pattern: #"<TimeSignature>[^<]*<[^>]*Denominator Value="(\d+)""#
    )
    static let currentEnd = try! NSRegularExpression(
        pattern: #"<CurrentEnd Value="([\d.]+)""#
    )
    static let sampleName = try! NSRegularExpression(
        pattern: #"<Name Value="([^"]+\.(wav|aif|aiff|mp3|flac|m4a))""#,
        options: .caseInsensitive
    )
    static let musicalKey = try! NSRegularExpression(
        pattern: #"<ScaleInformation>\s*<Root Value="(\d+)"\s*/>\s*<Name Value="(\d+)""#
    )
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

    /// Returns the raw decompressed XML string from an ALS file
    nonisolated func getRawXML(alsFilePath: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: alsFilePath.path) else {
            throw ALSParserError.fileNotFound
        }

        let compressedData = try Data(contentsOf: alsFilePath)
        let xmlData = try decompressGzip(data: compressedData)

        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            throw ALSParserError.invalidXML
        }

        return xmlString
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

        // Skip gzip header to find deflate payload
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

        // Streaming decompression — grows buffer as needed instead of pre-allocating 100MB
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        streamPtr.initialize(to: compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 0),
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil
        ))
        let initStatus = compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard initStatus == COMPRESSION_STATUS_OK else {
            streamPtr.deallocate()
            throw ALSParserError.decompressionFailed
        }
        defer {
            compression_stream_destroy(streamPtr)
            streamPtr.deallocate()
        }

        let chunkSize = 65_536 // 64KB output chunks
        var result = Data()
        result.reserveCapacity(min(deflateData.count * 10, 50_000_000))

        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { outputBuffer.deallocate() }

        try deflateData.withUnsafeBytes { sourceBuffer in
            let sourcePtr = sourceBuffer.bindMemory(to: UInt8.self)
            streamPtr.pointee.src_ptr = sourcePtr.baseAddress!
            streamPtr.pointee.src_size = sourcePtr.count

            while true {
                streamPtr.pointee.dst_ptr = outputBuffer
                streamPtr.pointee.dst_size = chunkSize

                let processStatus = compression_stream_process(streamPtr, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))

                let bytesWritten = chunkSize - streamPtr.pointee.dst_size
                if bytesWritten > 0 {
                    result.append(outputBuffer, count: bytesWritten)
                }

                switch processStatus {
                case COMPRESSION_STATUS_OK:
                    continue
                case COMPRESSION_STATUS_END:
                    return
                default:
                    throw ALSParserError.decompressionFailed
                }
            }
        }

        guard !result.isEmpty else {
            throw ALSParserError.decompressionFailed
        }

        return result
    }

    private nonisolated func parseXML(_ xmlString: String) -> ParsedProjectData {
        var result = ParsedProjectData()

        // Parse Ableton version - look in first 2000 chars for efficiency
        let headerSection = String(xmlString.prefix(2000))

        if let creatorStart = headerSection.range(of: "Creator=\"Ableton Live "),
           let creatorEnd = headerSection.range(of: "\"", range: creatorStart.upperBound..<headerSection.endIndex) {
            result.abletonVersion = String(headerSection[creatorStart.upperBound..<creatorEnd.lowerBound])
        }

        // Parse BPM - extract from Tempo block
        result.bpm = extractBPM(from: xmlString)

        // Parse time signature
        result.timeSignatureNumerator = extractFirstInt(from: xmlString, regex: ALSRegex.timeSignatureNumerator) ?? 4
        result.timeSignatureDenominator = extractFirstInt(from: xmlString, regex: ALSRegex.timeSignatureDenominator) ?? 4

        // Count tracks - fast counting without creating arrays
        result.audioTrackCount = countOccurrences(of: "<AudioTrack Id=", in: xmlString)
        result.midiTrackCount = countOccurrences(of: "<MidiTrack Id=", in: xmlString)
        result.returnTrackCount = countOccurrences(of: "<ReturnTrack Id=", in: xmlString)

        // Parse arrangement length
        if let beats = extractFirstDouble(from: xmlString, regex: ALSRegex.currentEnd),
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

    /// Fast occurrence counting without creating intermediate arrays
    private nonisolated func countOccurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let foundRange = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = foundRange.upperBound..<haystack.endIndex
        }
        return count
    }

    private nonisolated func extractBPM(from xmlString: String) -> Double? {
        // Find the Tempo block and extract the Manual value
        // The structure is: <Tempo>...<Manual Value="120" />...</Tempo>
        guard let tempoStart = xmlString.range(of: "<Tempo>"),
              let tempoEnd = xmlString.range(of: "</Tempo>", range: tempoStart.upperBound..<xmlString.endIndex) else {
            return nil
        }

        let tempoBlock = xmlString[tempoStart.lowerBound..<tempoEnd.upperBound]

        // Fast string-based extraction without regex
        guard let manualStart = tempoBlock.range(of: "<Manual Value=\""),
              let manualEnd = tempoBlock.range(of: "\"", range: manualStart.upperBound..<tempoBlock.endIndex) else {
            return nil
        }

        return Double(tempoBlock[manualStart.upperBound..<manualEnd.lowerBound])
    }

    private nonisolated func extractFirstDouble(from string: String, regex: NSRegularExpression) -> Double? {
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return Double(string[valueRange])
    }

    private nonisolated func extractFirstInt(from string: String, regex: NSRegularExpression) -> Int? {
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

        let range = NSRange(xmlString.startIndex..., in: xmlString)
        let matches = ALSRegex.sampleName.matches(in: xmlString, options: [], range: range)

        for match in matches.prefix(500) { // Limit to first 500 samples
            if let valueRange = Range(match.range(at: 1), in: xmlString) {
                names.insert(String(xmlString[valueRange]))
            }
        }

        return Array(names).sorted()
    }

    private nonisolated func extractPlugins(from xmlString: String) -> [String] {
        var plugins: Set<String> = []

        // Ableton 12.x: AU plugins — find <AuPluginInfo then <Name Value="..."/> nearby
        extractPluginsByTag(from: xmlString, openTag: "<AuPluginInfo", nameTag: "<Name Value=\"", into: &plugins)

        // Ableton 12.x: VST3 plugins — find <Vst3PluginInfo then <Name Value="..."/> nearby
        extractPluginsByTag(from: xmlString, openTag: "<Vst3PluginInfo", nameTag: "<Name Value=\"", into: &plugins)

        // Older Ableton / VST2: <VstPluginInfo then <PlugName Value="..."/>
        extractPluginsByTag(from: xmlString, openTag: "<VstPluginInfo", nameTag: "<PlugName Value=\"", into: &plugins)

        // Fallback: top-level <PlugName Value="..."/> (older format)
        extractPluginsByTag(from: xmlString, openTag: "<PlugName Value=\"", nameTag: nil, into: &plugins)

        return Array(plugins).sorted()
    }

    /// Fast string-search plugin extraction — no expensive multiline regex
    private nonisolated func extractPluginsByTag(
        from xmlString: String,
        openTag: String,
        nameTag: String?,
        into plugins: inout Set<String>
    ) {
        var searchStart = xmlString.startIndex

        for _ in 0..<200 { // Safety limit
            guard let tagRange = xmlString.range(of: openTag, range: searchStart..<xmlString.endIndex) else {
                break
            }

            searchStart = tagRange.upperBound

            if let nameTag = nameTag {
                // Search for the name tag within the next 2000 characters of the block
                let searchEnd = xmlString.index(tagRange.upperBound, offsetBy: 2000, limitedBy: xmlString.endIndex) ?? xmlString.endIndex
                guard let nameStart = xmlString.range(of: nameTag, range: tagRange.upperBound..<searchEnd) else {
                    continue
                }

                // Extract value between quotes
                let valueStart = nameStart.upperBound
                guard let quoteEnd = xmlString.range(of: "\"", range: valueStart..<searchEnd) else {
                    continue
                }

                let name = String(xmlString[valueStart..<quoteEnd.lowerBound])
                if isThirdPartyPlugin(name) {
                    plugins.insert(name)
                }
            } else {
                // The openTag itself contains the value (e.g. <PlugName Value="...)
                let valueStart = tagRange.upperBound
                let searchEnd = xmlString.index(valueStart, offsetBy: 200, limitedBy: xmlString.endIndex) ?? xmlString.endIndex
                guard let quoteEnd = xmlString.range(of: "\"", range: valueStart..<searchEnd) else {
                    continue
                }

                let name = String(xmlString[valueStart..<quoteEnd.lowerBound])
                if isThirdPartyPlugin(name) {
                    plugins.insert(name)
                }
            }
        }
    }

    private nonisolated func isThirdPartyPlugin(_ name: String) -> Bool {
        guard !name.isEmpty, name != "None" else { return false }
        return !isBuiltInDevice(name)
    }

    private nonisolated func isBuiltInDevice(_ name: String) -> Bool {
        let prefixes = ["Ableton", "Audio", "Auto", "Beat", "Corpus", "Delay", "Drum",
                        "EQ", "External", "Filter", "Flanger", "Gate", "Glue", "Grain",
                        "Limiter", "Looper", "MIDI", "Multiband", "Overdrive", "Pedal",
                        "Phaser", "Pitch", "Redux", "Resonator", "Reverb", "Saturator",
                        "Scale", "Simple", "Spectrum", "Tension", "Tuner", "Utility",
                        "Vinyl", "Vocoder", "Wavetable"]
        return prefixes.contains { name.hasPrefix($0) }
    }

    private nonisolated func extractMusicalKeys(from xmlString: String) -> [String] {
        var keys: Set<String> = []

        let range = NSRange(xmlString.startIndex..., in: xmlString)
        let matches = ALSRegex.musicalKey.matches(in: xmlString, options: [], range: range)

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
