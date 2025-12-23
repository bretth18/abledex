import Foundation
import Compression

/// Generates synthetic ALS (Ableton Live Set) files for testing purposes.
/// ALS files are gzip-compressed XML documents.
struct ALSFixtureGenerator {

    struct ProjectConfig {
        var creatorVersion: String = "12.1"
        var bpm: Double = 120.0
        var timeSignatureNumerator: Int = 4
        var timeSignatureDenominator: Int = 4
        var audioTrackCount: Int = 2
        var midiTrackCount: Int = 2
        var returnTrackCount: Int = 1
        var arrangementLength: Double = 960.0 // in beats
        var plugins: [String] = []
        var sampleNames: [String] = []

        static let minimal = ProjectConfig()

        static let complex = ProjectConfig(
            creatorVersion: "12.1.5",
            bpm: 128.0,
            timeSignatureNumerator: 4,
            timeSignatureDenominator: 4,
            audioTrackCount: 8,
            midiTrackCount: 16,
            returnTrackCount: 4,
            arrangementLength: 3840.0,
            plugins: ["Serum", "FabFilter Pro-Q 3", "Valhalla Room"],
            sampleNames: ["kick.wav", "snare.wav", "hihat.aif", "bass_loop.mp3"]
        )

        static let oddTimeSignature = ProjectConfig(
            bpm: 140.0,
            timeSignatureNumerator: 7,
            timeSignatureDenominator: 8
        )
    }

    /// Generates a gzip-compressed ALS file data from the given configuration
    static func generateALSData(config: ProjectConfig = .minimal) throws -> Data {
        let xml = generateXML(config: config)
        guard let xmlData = xml.data(using: .utf8) else {
            throw FixtureError.encodingFailed
        }
        return try compressToGzip(data: xmlData)
    }

    /// Writes a synthetic ALS file to the specified URL
    static func writeALSFile(to url: URL, config: ProjectConfig = .minimal) throws {
        let data = try generateALSData(config: config)
        try data.write(to: url)
    }

    /// Generates raw (uncompressed) XML for testing invalid gzip scenarios
    static func generateRawXML(config: ProjectConfig = .minimal) -> String {
        generateXML(config: config)
    }

    // MARK: - Private

    private static func generateXML(config: ProjectConfig) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton MajorVersion="5" MinorVersion="12.1.0" SchemaChangeCount="3" Creator="Ableton Live \(config.creatorVersion)" Revision="">
        <LiveSet>
            <Tempo>
                <LomId Value="0" />
                <Manual Value="\(config.bpm)" />
                <MidiControllerRange>
                    <Min Value="60" />
                    <Max Value="200" />
                </MidiControllerRange>
            </Tempo>
            <TimeSignature><Numerator Value="\(config.timeSignatureNumerator)" /><Denominator Value="\(config.timeSignatureDenominator)" /></TimeSignature>
            <CurrentEnd Value="\(config.arrangementLength)" />
            <Tracks>
        """

        // Generate audio tracks
        for i in 0..<config.audioTrackCount {
            xml += """

                <AudioTrack Id="\(i)">
                    <Name Value="Audio \(i + 1)" />
                </AudioTrack>
            """
        }

        // Generate MIDI tracks
        for i in 0..<config.midiTrackCount {
            xml += """

                <MidiTrack Id="\(config.audioTrackCount + i)">
                    <Name Value="MIDI \(i + 1)" />
                </MidiTrack>
            """
        }

        // Generate return tracks
        for i in 0..<config.returnTrackCount {
            xml += """

                <ReturnTrack Id="\(config.audioTrackCount + config.midiTrackCount + i)">
                    <Name Value="Return \(i + 1)" />
                </ReturnTrack>
            """
        }

        xml += """

            </Tracks>
        """

        // Add plugins
        if !config.plugins.isEmpty {
            xml += """

            <PluginDevices>
            """
            for plugin in config.plugins {
                xml += """

                <PluginDevice>
                    <PlugName Value="\(plugin)" />
                </PluginDevice>
                """
            }
            xml += """

            </PluginDevices>
            """
        }

        // Add samples
        if !config.sampleNames.isEmpty {
            xml += """

            <SampleRefs>
            """
            for sample in config.sampleNames {
                xml += """

                <SampleRef>
                    <Name Value="\(sample)" />
                </SampleRef>
                """
            }
            xml += """

            </SampleRefs>
            """
        }

        xml += """

        </LiveSet>
        </Ableton>
        """

        return xml
    }

    private static func compressToGzip(data: Data) throws -> Data {
        // Gzip header
        var gzipData = Data([
            0x1f, 0x8b, // Magic number
            0x08,       // Compression method (deflate)
            0x00,       // Flags
            0x00, 0x00, 0x00, 0x00, // Modification time
            0x00,       // Extra flags
            0xff        // OS (unknown)
        ])

        // Compress the data using zlib
        let compressedData = try compressDeflate(data: data)
        gzipData.append(compressedData)

        // CRC32 and original size (little-endian)
        let crc = crc32(data: data)
        gzipData.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
        gzipData.append(contentsOf: withUnsafeBytes(of: UInt32(data.count).littleEndian) { Array($0) })

        return gzipData
    }

    private static func compressDeflate(data: Data) throws -> Data {
        let destinationBufferSize = data.count + 1024
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

        let compressedSize = data.withUnsafeBytes { sourceBuffer in
            compression_encode_buffer(
                &destinationBuffer,
                destinationBufferSize,
                sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else {
            throw FixtureError.compressionFailed
        }

        return Data(destinationBuffer.prefix(compressedSize))
    }

    private static func crc32(data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let polynomial: UInt32 = 0xEDB88320

        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ polynomial
                } else {
                    crc >>= 1
                }
            }
        }

        return ~crc
    }

    enum FixtureError: Error {
        case encodingFailed
        case compressionFailed
    }
}
