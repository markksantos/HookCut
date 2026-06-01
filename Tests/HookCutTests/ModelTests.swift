import XCTest
@testable import HookCut

final class ModelTests: XCTestCase {

    // MARK: - RationalTime

    func testRationalTimeSeconds() {
        let rt = RationalTime(numerator: 1001, denominator: 30000)
        XCTAssertEqual(rt.seconds, 1001.0 / 30000.0, accuracy: 1e-9)
    }

    func testRationalTimeFCPXMLString() {
        XCTAssertEqual(RationalTime(numerator: 1001, denominator: 30000).fcpxmlString, "1001/30000s")
    }

    func testRationalTimeReducedUsesGCD() {
        let reduced = RationalTime(numerator: 200, denominator: 6000).reduced
        XCTAssertEqual(reduced.numerator, 1)
        XCTAssertEqual(reduced.denominator, 30)
    }

    func testRationalTimeFromSecondsSnapsToFrameBoundary() {
        // 1 second at 30fps -> 30 frames -> 3000/3000s (before reduction)
        let rt = RationalTime.fromSeconds(1.0, frameRate: .fps30)
        XCTAssertEqual(rt.seconds, 1.0, accuracy: 1e-6)
        // A sub-frame value snaps to the nearest frame.
        let snapped = RationalTime.fromSeconds(1.0 + (1.0 / 30.0) * 0.4, frameRate: .fps30)
        XCTAssertEqual(snapped.seconds, 1.0, accuracy: 1e-6)
    }

    // MARK: - FrameRate

    func testFrameRateDropFrameDetection() {
        XCTAssertTrue(FrameRate.fps29_97.isDropFrame)
        XCTAssertTrue(FrameRate.fps23_976.isDropFrame)
        XCTAssertTrue(FrameRate.fps59_94.isDropFrame)
        XCTAssertFalse(FrameRate.fps30.isDropFrame)
        XCTAssertFalse(FrameRate.fps25.isDropFrame)
    }

    func testFrameRateDetectFromRawFPS() {
        XCTAssertEqual(FrameRate.detect(from: 29.97), .fps29_97)
        XCTAssertEqual(FrameRate.detect(from: 23.98), .fps23_976)
        XCTAssertEqual(FrameRate.detect(from: 60.0), .fps60)
        XCTAssertEqual(FrameRate.detect(from: 24.0), .fps24)
    }

    func testFrameRateFPSValues() {
        XCTAssertEqual(FrameRate.fps29_97.fps, 30000.0 / 1001.0, accuracy: 1e-9)
        XCTAssertEqual(FrameRate.fps24.fps, 24.0, accuracy: 1e-9)
    }

    // MARK: - Highlight invariants

    func testHighlightClampsRating() {
        let high = Highlight(sequenceNumber: 1, type: .insight, rating: 9, text: "t",
                             context: "c", startTime: 0, endTime: 1, speakerId: UUID())
        XCTAssertEqual(high.rating, 5)
        let low = Highlight(sequenceNumber: 1, type: .insight, rating: -3, text: "t",
                            context: "c", startTime: 0, endTime: 1, speakerId: UUID())
        XCTAssertEqual(low.rating, 1)
    }

    func testHighlightEnsuresPositiveDuration() {
        let h = Highlight(sequenceNumber: 1, type: .insight, rating: 3, text: "t",
                          context: "c", startTime: 10, endTime: 5, speakerId: UUID())
        XCTAssertGreaterThan(h.endTime, h.startTime)
        XCTAssertEqual(h.duration, h.endTime - h.startTime, accuracy: 1e-9)
    }

    // MARK: - AnalysisResult aggregates

    func testApprovedHighlightsAndDuration() {
        let sid = UUID()
        let approved = Highlight(sequenceNumber: 1, type: .insight, rating: 5, text: "a",
                                 context: "", startTime: 0, endTime: 4, speakerId: sid, isApproved: true)
        let rejected = Highlight(sequenceNumber: 2, type: .humor, rating: 2, text: "b",
                                 context: "", startTime: 5, endTime: 9, speakerId: sid, isApproved: false)
        let result = AnalysisResult(episodeSummary: "s", speakers: [],
                                    highlights: [approved, rejected], suggestedTeaserOrder: [])
        XCTAssertEqual(result.approvedHighlights.count, 1)
        XCTAssertEqual(result.approvedDuration, 4.0, accuracy: 1e-9)
    }

    // MARK: - CostEstimator

    func testCostEstimatorLocalTranscriptionIsFree() {
        let cloud = CostEstimatorService.estimate(durationSeconds: 600, provider: .openAI, transcriptionEngine: .cloud)
        let local = CostEstimatorService.estimate(durationSeconds: 600, provider: .openAI, transcriptionEngine: .local)
        XCTAssertGreaterThan(cloud.whisperCost, 0)
        XCTAssertEqual(local.whisperCost, 0)
        XCTAssertLessThan(local.totalCost, cloud.totalCost)
    }

    func testCostEstimatorOllamaAnalysisIsFree() {
        let est = CostEstimatorService.estimate(durationSeconds: 600, provider: .ollama, transcriptionEngine: .local)
        // Fully local: no whisper cost, no analysis cost.
        XCTAssertEqual(est.totalCost, 0, accuracy: 1e-9)
    }

    func testCostEstimatorScalesWithDuration() {
        let short = CostEstimatorService.estimate(durationSeconds: 60, provider: .openAI)
        let long = CostEstimatorService.estimate(durationSeconds: 600, provider: .openAI)
        XCTAssertGreaterThan(long.totalCost, short.totalCost)
    }

    // MARK: - Settings Codable round-trip (Set<HighlightType> RawRepresentable)

    func testAppSettingsCodableRoundTrip() throws {
        var settings = AppSettings.default
        settings.openAIAPIKey = "sk-test"
        settings.enabledHighlightTypes = [.humor, .insight]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.openAIAPIKey, "sk-test")
        XCTAssertEqual(decoded.enabledHighlightTypes, [.humor, .insight])
    }
}
