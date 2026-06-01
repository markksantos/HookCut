import XCTest
@testable import HookCut

final class ExporterTests: XCTestCase {

    // MARK: - Fixtures

    private func makeAnalysis(text: String = "This is a great point", context: String = "") -> AnalysisResult {
        let speaker = Speaker(name: "Alice", role: "host", color: "#007AFF")
        let h1 = Highlight(sequenceNumber: 1, type: .hotTake, rating: 5, text: text,
                           context: context, startTime: 10.0, endTime: 14.0,
                           speakerId: speaker.id, isApproved: true)
        let h2 = Highlight(sequenceNumber: 2, type: .insight, rating: 4, text: "Second clip",
                           context: "ctx", startTime: 30.0, endTime: 36.0,
                           speakerId: speaker.id, isApproved: true)
        let rejected = Highlight(sequenceNumber: 3, type: .humor, rating: 2, text: "ignored",
                                 context: "", startTime: 50.0, endTime: 52.0,
                                 speakerId: speaker.id, isApproved: false)
        return AnalysisResult(episodeSummary: "A test episode.",
                              speakers: [speaker],
                              highlights: [h1, h2, rejected],
                              suggestedTeaserOrder: [1, 2])
    }

    private func makeMediaFile() -> MediaFileInfo {
        MediaFileInfo(url: URL(fileURLWithPath: "/tmp/test video.mp4"),
                      fileName: "test video.mp4",
                      fileSize: 1_000_000,
                      duration: 120.0,
                      isVideoFile: true,
                      videoWidth: 1920,
                      videoHeight: 1080,
                      frameRate: .fps29_97,
                      codec: "avc1")
    }

    private var config: ExportConfig {
        ExportConfig(format: .fcpxml, gapDuration: 1.0, includeMarkers: true, projectName: "Test")
    }

    // MARK: - FCPXML

    func testFCPXMLProducesValidParseableXML() throws {
        let data = try FCPXMLGenerator().generate(analysis: makeAnalysis(), mediaFile: makeMediaFile(), config: config)
        // Must round-trip through XMLDocument without error.
        let doc = try XMLDocument(data: data)
        XCTAssertEqual(doc.rootElement()?.name, "fcpxml")
        let clips = try doc.nodes(forXPath: "//asset-clip")
        XCTAssertEqual(clips.count, 2, "Only the 2 approved highlights should be exported")
    }

    func testFCPXMLDoesNotDoubleEscapeEntities() throws {
        // The bug: text was manually escaped AND then escaped again by XMLNode.
        let data = try FCPXMLGenerator().generate(
            analysis: makeAnalysis(text: "AT&T is <the> \"best\""),
            mediaFile: makeMediaFile(), config: config)
        let xml = String(data: data, encoding: .utf8)!
        XCTAssertFalse(xml.contains("&amp;amp;"), "Ampersand must not be double-escaped")
        XCTAssertFalse(xml.contains("&amp;lt;"), "Less-than must not be double-escaped")
        // Decoded value of the name attribute should contain the literal text.
        let doc = try XMLDocument(data: data)
        let clipNames = try doc.nodes(forXPath: "//asset-clip/@name").compactMap { $0.stringValue }
        XCTAssertTrue(clipNames.contains { $0.contains("AT&T is <the> \"best\"") },
                      "Round-tripped clip name should equal the original text, got: \(clipNames)")
    }

    func testFCPXMLThrowsWhenNoApprovedHighlights() {
        let speaker = Speaker(name: "A")
        let rejected = Highlight(sequenceNumber: 1, type: .humor, rating: 1, text: "x",
                                 context: "", startTime: 0, endTime: 1, speakerId: speaker.id, isApproved: false)
        let analysis = AnalysisResult(episodeSummary: "", speakers: [speaker], highlights: [rejected], suggestedTeaserOrder: [])
        XCTAssertThrowsError(try FCPXMLGenerator().generate(analysis: analysis, mediaFile: makeMediaFile(), config: config))
    }

    // MARK: - Premiere XML

    func testPremiereXMLProducesValidParseableXML() throws {
        let data = try PremiereXMLGenerator().generate(analysis: makeAnalysis(), mediaFile: makeMediaFile(), config: config)
        let doc = try XMLDocument(data: data)
        XCTAssertEqual(doc.rootElement()?.name, "xmeml")
        let clipItems = try doc.nodes(forXPath: "//clipitem")
        // One video + one audio clipitem per approved highlight = 4.
        XCTAssertEqual(clipItems.count, 4)
    }

    func testPremiereXMLDoesNotDoubleEscapeEntities() throws {
        let data = try PremiereXMLGenerator().generate(
            analysis: makeAnalysis(text: "Tom & Jerry"),
            mediaFile: makeMediaFile(), config: config)
        let xml = String(data: data, encoding: .utf8)!
        XCTAssertFalse(xml.contains("&amp;amp;"))
        let doc = try XMLDocument(data: data)
        let names = try doc.nodes(forXPath: "//clipitem/name").compactMap { $0.stringValue }
        XCTAssertTrue(names.contains { $0.contains("Tom & Jerry") })
    }

    // MARK: - EDL

    func testEDLTimecodeAndStructure() throws {
        let data = try EDLGenerator().generate(analysis: makeAnalysis(), mediaFile: makeMediaFile(), config: config)
        let edl = String(data: data, encoding: .utf8)!
        XCTAssertTrue(edl.hasPrefix("TITLE:"))
        // 29.97 is drop-frame -> FCM line + ";" timecode separator.
        XCTAssertTrue(edl.contains("FCM: DROP FRAME"))
        XCTAssertTrue(edl.contains(";"))
        // Two events, zero-padded.
        XCTAssertTrue(edl.contains("001"))
        XCTAssertTrue(edl.contains("002"))
    }

    func testEDLNonDropFrameUsesColonSeparator() throws {
        var media = makeMediaFile()
        media = MediaFileInfo(url: media.url, fileName: media.fileName, fileSize: media.fileSize,
                              duration: media.duration, isVideoFile: media.isVideoFile,
                              videoWidth: media.videoWidth, videoHeight: media.videoHeight,
                              frameRate: .fps30, codec: media.codec)
        let data = try EDLGenerator().generate(analysis: makeAnalysis(), mediaFile: media, config: config)
        let edl = String(data: data, encoding: .utf8)!
        XCTAssertTrue(edl.contains("FCM: NON-DROP FRAME"))
    }

    // MARK: - SRT

    func testSRTFormat() throws {
        let data = try SRTExporter().generate(analysis: makeAnalysis())
        let srt = String(data: data, encoding: .utf8)!
        // First cue index, then a "start --> end" line with comma ms separator.
        XCTAssertTrue(srt.hasPrefix("1\n"))
        XCTAssertTrue(srt.contains(" --> "))
        XCTAssertTrue(srt.contains("00:00:10,000 --> 00:00:14,000"))
    }

    // MARK: - CSV

    func testCSVHeaderAndEscaping() throws {
        let analysis = makeAnalysis(text: "He said \"hello, world\"", context: "a, b")
        let data = try CSVExporter().generate(analysis: analysis, mediaFile: makeMediaFile())
        let csv = String(data: data, encoding: .utf8)!
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "#,Speaker,Type,Rating,Start Time,End Time,Duration,Text,Context")
        // Field with comma + quote must be quoted and quotes doubled.
        XCTAssertTrue(csv.contains("\"He said \"\"hello, world\"\"\""))
    }

    // MARK: - Plain Text

    func testPlainTextWithoutTranscriptListsHighlights() throws {
        let data = try PlainTextExporter().generate(analysis: makeAnalysis(), transcript: nil)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("HOOKCUT HIGHLIGHTS EXPORT"))
        XCTAssertTrue(text.contains("This is a great point"))
        XCTAssertFalse(text.contains("ignored"), "Rejected highlights should not appear")
    }

    func testPlainTextWithTranscriptAnnotatesInline() throws {
        let seg = TranscriptionSegment(speaker: "Alice", text: "This is a great point", start: 10.0, end: 14.0)
        let transcript = TranscriptionResult(segments: [seg], fullText: seg.text, duration: 120, language: "en")
        let data = try PlainTextExporter().generate(analysis: makeAnalysis(), transcript: transcript)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("[HIGHLIGHT START"))
        XCTAssertTrue(text.contains("[HIGHLIGHT END]"))
    }
}
