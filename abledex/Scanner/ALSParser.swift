//
//  ALSParser.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import Foundation
import Compression

/// A sample file reference extracted from a `<FileRef>` block.
/// Modern Live (10/11/12) stores both an absolute `<Path Value="...">` and a
/// project-relative `<RelativePath Value="...">`. Either may be absent.
nonisolated struct SampleFileReference: Sendable, Hashable {
    let absolutePath: String?
    let relativePath: String?

    nonisolated init(absolutePath: String? = nil, relativePath: String? = nil) {
        self.absolutePath = absolutePath
        self.relativePath = relativePath
    }
}

nonisolated struct ParsedProjectData: Sendable {
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
    var sampleFileReferences: [SampleFileReference] = []
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
        sampleFileReferences: [SampleFileReference] = [],
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
        self.sampleFileReferences = sampleFileReferences
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

nonisolated struct ALSParser: Sendable {

    init() {}

    /// Single streaming pass: gzip chunks feed the byte scanner directly, so
    /// peak memory is a small carry buffer, never the decompressed document
    /// (large sets exceed 100MB of XML and several parses run concurrently).
    func parse(alsFilePath: URL) throws -> ParsedProjectData {
        guard FileManager.default.fileExists(atPath: alsFilePath.path) else {
            throw ALSParserError.fileNotFound
        }

        let compressedData = try Data(contentsOf: alsFilePath, options: .mappedIfSafe)
        let scanner = ALSStreamScanner()
        try decompressGzip(data: compressedData) { chunk in
            scanner.consume(chunk)
        }
        return scanner.finish()
    }

    /// Returns the raw decompressed XML string from an ALS file
    func getRawXML(alsFilePath: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: alsFilePath.path) else {
            throw ALSParserError.fileNotFound
        }

        let compressedData = try Data(contentsOf: alsFilePath, options: .mappedIfSafe)
        var xmlData = Data()
        try decompressGzip(data: compressedData) { chunk in
            xmlData.append(chunk.baseAddress!, count: chunk.count)
        }

        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            throw ALSParserError.invalidXML
        }

        return xmlString
    }

    /// Streaming gzip decompression: emits decompressed bytes to `onChunk` in
    /// 64KB pieces instead of accumulating the whole document.
    private func decompressGzip(data: Data, onChunk: (UnsafeBufferPointer<UInt8>) -> Void) throws {
        guard data.count > 10 else {
            throw ALSParserError.decompressionFailed
        }

        // Check for gzip magic number
        guard data[0] == 0x1f && data[1] == 0x8b else {
            // Not gzipped; might be raw XML
            guard String(data: data, encoding: .utf8) != nil else {
                throw ALSParserError.invalidXML
            }
            data.withUnsafeBytes { raw in
                onChunk(raw.bindMemory(to: UInt8.self))
            }
            return
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
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { outputBuffer.deallocate() }

        var producedAnyOutput = false

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
                    producedAnyOutput = true
                    onChunk(UnsafeBufferPointer(start: outputBuffer, count: bytesWritten))
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

        guard producedAnyOutput else {
            throw ALSParserError.decompressionFailed
        }
    }
}

// MARK: - Streaming Byte Scanner

/// Extracts every project metric in one pass over the decompressed XML bytes,
/// fed chunk-by-chunk. Only captured attribute values are materialized; at
/// most `lookahead` bytes carry over between chunks for straddling tokens.
///
/// Attribute values in ALS XML never contain a raw '<' (it is entity-escaped),
/// so scanning for '<' via memchr never false-positives inside a value.
private nonisolated final class ALSStreamScanner {
    private var result = ParsedProjectData()

    /// Unprocessed tail of the previous chunk + the current chunk.
    private var buffer: [UInt8] = []
    /// Absolute document offset of buffer[0].
    private var processedOffset = 0
    private var headerParsed = false

    /// Tokens starting within `lookahead` bytes of the buffer end are deferred
    /// to the next chunk so a tag + its attribute value are always fully
    /// visible when processed. Must exceed the longest expected tag + value.
    private static let lookahead = 16_384

    // Tempo: first <Tempo> block's <Manual Value="..."> is the project BPM.
    private var inTempo = false
    private var bpmFound = false

    // Time signature: the tag immediately following <TimeSignature> carries
    // "...Numerator Value" / "...Denominator Value" attributes.
    private var timeSignaturePending = false

    // Arrangement end (first <CurrentEnd Value="...">), converted to seconds
    // at finish() once BPM is known.
    private var currentEndBeats: Double?

    // Sample references: only <FileRef> blocks inside <SampleRef> count
    // (Live uses FileRef for presets, skins, and history too), and only the
    // first FileRef per SampleRef.
    private var inSampleRef = false
    private var sampleRefHadFileRef = false
    private var inFileRef = false
    private var pendingAbsolutePath: String?
    private var pendingRelativePath: String?
    private var seenReferences = Set<SampleFileReference>()

    // Plugins: an info tag opens a window; the next name tag within
    // `pluginNameWindow` bytes is the plugin's name.
    private enum PendingPlugin { case au, vst3, vst2 }
    private var pendingPlugin: PendingPlugin?
    private var pendingPluginDeadline = 0
    private static let pluginNameWindow = 2000
    private var pluginNames = Set<String>()

    private var sampleNames = Set<String>()

    // Musical key: <ScaleInformation> → <Root Value="n"/> → <Name Value="m"/>
    private enum ScaleState { case none, expectRoot, expectName(root: Int) }
    private var scaleState = ScaleState.none
    private var musicalKeys = Set<String>()

    private static let maxSampleNames = 500
    private static let maxReferences = 500
    private static let maxKeys = 100
    private static let maxPlugins = 400

    func consume(_ chunk: UnsafeBufferPointer<UInt8>) {
        buffer.append(contentsOf: chunk)
        if !headerParsed {
            parseHeader()
            headerParsed = true
        }
        let processed = scan(isFinal: false)
        if processed > 0 {
            buffer.removeSubrange(0..<processed)
            processedOffset += processed
        }
    }

    func finish() -> ParsedProjectData {
        if !headerParsed {
            parseHeader()
            headerParsed = true
        }
        _ = scan(isFinal: true)
        buffer.removeAll(keepingCapacity: false)

        if result.timeSignatureNumerator == nil { result.timeSignatureNumerator = 4 }
        if result.timeSignatureDenominator == nil { result.timeSignatureDenominator = 4 }
        if let beats = currentEndBeats, let bpm = result.bpm, bpm > 0 {
            result.duration = (beats / bpm) * 60.0
        }
        result.plugins = pluginNames.sorted()
        result.samplePaths = sampleNames.sorted()
        result.musicalKeys = musicalKeys.sorted()
        return result
    }

    // MARK: Header (Ableton version attributes, always in the first bytes)

    private func parseHeader() {
        let limit = min(2000, buffer.count)
        buffer.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            if let creator = find("Creator=\"Ableton Live ", in: base, 0, limit),
               let (value, _) = quotedValue(base, creator, limit) {
                result.abletonVersion = value
            }
            if let minor = find("MinorVersion=\"", in: base, 0, limit),
               let (value, _) = quotedValue(base, minor, limit) {
                result.abletonMinorVersion = value.isEmpty ? nil : value
            }
        }
    }

    // MARK: Scan loop

    /// Processes all '<' tokens below the carry threshold; returns the index
    /// up to which the buffer has been fully consumed.
    private func scan(isFinal: Bool) -> Int {
        let limit = isFinal ? buffer.count : max(0, buffer.count - Self.lookahead)
        guard limit > 0 else { return 0 }

        buffer.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            let end = buf.count
            var i = 0
            while i < limit {
                let searchStart = UnsafeRawPointer(base + i)
                guard let found = memchr(searchStart, 0x3C, limit - i) else { break }
                let token = i + (UnsafeRawPointer(found) - searchStart)
                processToken(base, token, end)
                i = token + 1
            }
        }
        return limit
    }

    private func processToken(_ buf: UnsafePointer<UInt8>, _ t: Int, _ end: Int) {
        // This token is "the tag after <TimeSignature>" for a pending signature.
        if timeSignaturePending {
            timeSignaturePending = false
            examineTimeSignatureTag(buf, t, end)
        }

        // Scale sequence advances (or resets) on every tag.
        switch scaleState {
        case .none:
            break
        case .expectRoot:
            scaleState = .none
            if match(buf, t, end, "<Root Value=\""),
               let (value, _) = quotedValue(buf, t + 13, end),
               let root = Int(value) {
                scaleState = .expectName(root: root)
            }
        case .expectName(let root):
            scaleState = .none
            if match(buf, t, end, "<Name Value=\""),
               let (value, _) = quotedValue(buf, t + 13, end),
               let scaleName = Int(value),
               musicalKeys.count < Self.maxKeys,
               let key = formatMusicalKey(root: root, scaleName: scaleName) {
                musicalKeys.insert(key)
            }
            // Fall through: the same <Name ...> token may also be a sample/plugin name
        }

        guard t + 1 < end else { return }

        switch buf[t + 1] {
        case UInt8(ascii: "A"):
            if match(buf, t, end, "<AudioTrack Id=") {
                result.audioTrackCount += 1
            } else if match(buf, t, end, "<AuPluginInfo") {
                pendingPlugin = .au
                pendingPluginDeadline = processedOffset + t + Self.pluginNameWindow
            }

        case UInt8(ascii: "C"):
            if currentEndBeats == nil, match(buf, t, end, "<CurrentEnd Value=\""),
               let (value, _) = quotedValue(buf, t + 19, end) {
                currentEndBeats = Double(value)
            }

        case UInt8(ascii: "F"):
            if match(buf, t, end, "<FileRef"),
               inSampleRef, !sampleRefHadFileRef,
               result.sampleFileReferences.count < Self.maxReferences {
                inFileRef = true
                sampleRefHadFileRef = true
                pendingAbsolutePath = nil
                pendingRelativePath = nil
            }

        case UInt8(ascii: "M"):
            if match(buf, t, end, "<MidiTrack Id=") {
                result.midiTrackCount += 1
            } else if inTempo, !bpmFound, match(buf, t, end, "<Manual Value=\""),
                      let (value, _) = quotedValue(buf, t + 15, end) {
                result.bpm = Double(value)
                bpmFound = true
                inTempo = false
            }

        case UInt8(ascii: "N"):
            if match(buf, t, end, "<Name Value=\""),
               let (value, _) = quotedValue(buf, t + 13, end) {
                handleNameValue(value, at: processedOffset + t)
            }

        case UInt8(ascii: "P"):
            if match(buf, t, end, "<PlugName Value=\"") {
                if let (value, _) = quotedValue(buf, t + 17, end) {
                    if isThirdPartyPlugin(value), pluginNames.count < Self.maxPlugins {
                        pluginNames.insert(value)
                    }
                    if case .vst2 = pendingPlugin {
                        pendingPlugin = nil
                    }
                }
            } else if inFileRef, pendingAbsolutePath == nil, match(buf, t, end, "<Path Value=\""),
                      let (value, _) = quotedValue(buf, t + 13, end) {
                let unescaped = unescapeXMLEntities(value)
                pendingAbsolutePath = unescaped.isEmpty ? nil : unescaped
            }

        case UInt8(ascii: "R"):
            if match(buf, t, end, "<ReturnTrack Id=") {
                result.returnTrackCount += 1
            } else if inFileRef, pendingRelativePath == nil, match(buf, t, end, "<RelativePath Value=\""),
                      let (value, _) = quotedValue(buf, t + 21, end) {
                let unescaped = unescapeXMLEntities(value)
                pendingRelativePath = unescaped.isEmpty ? nil : unescaped
            }

        case UInt8(ascii: "S"):
            if match(buf, t, end, "<SampleRef>") {
                if inFileRef { emitFileReference() }
                inSampleRef = true
                sampleRefHadFileRef = false
            } else if match(buf, t, end, "<ScaleInformation>") {
                scaleState = .expectRoot
            }

        case UInt8(ascii: "T"):
            if match(buf, t, end, "<Tempo>") {
                if !bpmFound { inTempo = true }
            } else if match(buf, t, end, "<TimeSignature>") {
                if result.timeSignatureNumerator == nil || result.timeSignatureDenominator == nil {
                    timeSignaturePending = true
                }
            }

        case UInt8(ascii: "V"):
            if match(buf, t, end, "<Vst3PluginInfo") {
                pendingPlugin = .vst3
                pendingPluginDeadline = processedOffset + t + Self.pluginNameWindow
            } else if match(buf, t, end, "<VstPluginInfo") {
                pendingPlugin = .vst2
                pendingPluginDeadline = processedOffset + t + Self.pluginNameWindow
            }

        case UInt8(ascii: "/"):
            if match(buf, t, end, "</Tempo>") {
                inTempo = false
            } else if match(buf, t, end, "</FileRef>") {
                if inFileRef { emitFileReference() }
            } else if match(buf, t, end, "</SampleRef>") {
                if inFileRef { emitFileReference() }
                inSampleRef = false
            }

        default:
            break
        }
    }

    /// A `<Name Value="...">` serves several masters: the plugin name following
    /// an AU/VST3 info tag, and audio-extension names counted as samples.
    private func handleNameValue(_ value: String, at absoluteOffset: Int) {
        if let pending = pendingPlugin, pending != .vst2 {
            pendingPlugin = nil
            if absoluteOffset <= pendingPluginDeadline,
               isThirdPartyPlugin(value), pluginNames.count < Self.maxPlugins {
                pluginNames.insert(value)
            }
        }

        if sampleNames.count < Self.maxSampleNames, hasAudioExtension(value) {
            sampleNames.insert(value)
        }
    }

    private static let audioExtensions = [".wav", ".aif", ".aiff", ".mp3", ".flac", ".m4a"]

    private func hasAudioExtension(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return Self.audioExtensions.contains { ext in
            lowered.hasSuffix(ext) && lowered.count > ext.count
        }
    }

    private func emitFileReference() {
        inFileRef = false
        guard pendingAbsolutePath != nil || pendingRelativePath != nil else { return }
        let reference = SampleFileReference(
            absolutePath: pendingAbsolutePath,
            relativePath: pendingRelativePath
        )
        pendingAbsolutePath = nil
        pendingRelativePath = nil
        if seenReferences.insert(reference).inserted {
            result.sampleFileReferences.append(reference)
        }
    }

    /// The tag at `t` follows a `<TimeSignature>`; its attributes carry the
    /// numerator/denominator (e.g. `<RemoteableTimeSignature Numerator Value="4" ...>`
    /// or separate `<...Numerator Value="4">` tags on older versions).
    private func examineTimeSignatureTag(_ buf: UnsafePointer<UInt8>, _ t: Int, _ end: Int) {
        let searchLimit = min(end, t + 512)
        guard let close = find(">", in: buf, t, searchLimit) else { return }

        if result.timeSignatureNumerator == nil,
           let numStart = find("Numerator Value=\"", in: buf, t, close),
           let (value, _) = quotedValue(buf, numStart, close),
           let numerator = Int(value) {
            result.timeSignatureNumerator = numerator
        }
        if result.timeSignatureDenominator == nil,
           let denStart = find("Denominator Value=\"", in: buf, t, close),
           let (value, _) = quotedValue(buf, denStart, close),
           let denominator = Int(value) {
            result.timeSignatureDenominator = denominator
        }
    }

    // MARK: Byte matching helpers

    /// True when the bytes at `i` are exactly `pattern`.
    private func match(_ buf: UnsafePointer<UInt8>, _ i: Int, _ end: Int, _ pattern: StaticString) -> Bool {
        let length = pattern.utf8CodeUnitCount
        guard i + length <= end else { return false }
        return pattern.withUTF8Buffer { patternBuf in
            memcmp(buf + i, patternBuf.baseAddress!, length) == 0
        }
    }

    /// First occurrence of `pattern` in buf[start..<end], returning the index
    /// just past the pattern (i.e. where a value capture would begin).
    private func find(_ pattern: StaticString, in buf: UnsafePointer<UInt8>, _ start: Int, _ end: Int) -> Int? {
        let length = pattern.utf8CodeUnitCount
        guard length > 0, end - start >= length else { return nil }
        return pattern.withUTF8Buffer { patternBuf in
            let first = patternBuf[0]
            var i = start
            while i <= end - length {
                let searchStart = UnsafeRawPointer(buf + i)
                guard let found = memchr(searchStart, Int32(first), end - length - i + 1) else { return nil }
                let candidate = i + (UnsafeRawPointer(found) - searchStart)
                if memcmp(buf + candidate, patternBuf.baseAddress!, length) == 0 {
                    return candidate + length
                }
                i = candidate + 1
            }
            return nil
        }
    }

    /// The value bytes from `from` up to the next '"', as a String.
    /// nil when no closing quote is found within bounds (or within 8KB).
    private func quotedValue(_ buf: UnsafePointer<UInt8>, _ from: Int, _ end: Int) -> (String, Int)? {
        let maxLength = min(end - from, 8192)
        guard maxLength > 0 else { return nil }
        let searchStart = UnsafeRawPointer(buf + from)
        guard let found = memchr(searchStart, 0x22, maxLength) else { return nil }
        let quoteIndex = from + (UnsafeRawPointer(found) - searchStart)
        let value = String(decoding: UnsafeBufferPointer(start: buf + from, count: quoteIndex - from), as: UTF8.self)
        return (value, quoteIndex + 1)
    }

    // MARK: Value helpers

    /// Decodes the five predefined XML entities (paths may contain & or ')
    private func unescapeXMLEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        return string
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func isThirdPartyPlugin(_ name: String) -> Bool {
        guard !name.isEmpty, name != "None" else { return false }
        return !isBuiltInDevice(name)
    }

    private func isBuiltInDevice(_ name: String) -> Bool {
        let prefixes = ["Ableton", "Audio", "Auto", "Beat", "Corpus", "Delay", "Drum",
                        "EQ", "External", "Filter", "Flanger", "Gate", "Glue", "Grain",
                        "Limiter", "Looper", "MIDI", "Multiband", "Overdrive", "Pedal",
                        "Phaser", "Pitch", "Redux", "Resonator", "Reverb", "Saturator",
                        "Scale", "Simple", "Spectrum", "Tension", "Tuner", "Utility",
                        "Vinyl", "Vocoder", "Wavetable"]
        return prefixes.contains { name.hasPrefix($0) }
    }

    private func formatMusicalKey(root: Int, scaleName: Int) -> String? {
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
