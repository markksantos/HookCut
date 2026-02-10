import Foundation

/// Concrete implementation of TranscriptionServiceProtocol that orchestrates the full pipeline
final class TranscriptionService: TranscriptionServiceProtocol {

    func extractAudio(
        from url: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        try await AudioExtractor.extractAudio(from: url, progressHandler: progressHandler)
    }

    func transcribe(
        audioURL: URL,
        apiKey: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> TranscriptionResult {
        try await WhisperService.transcribe(
            audioURL: audioURL,
            apiKey: apiKey,
            progressHandler: progressHandler
        )
    }

    func identifySpeakers(
        transcript: TranscriptionResult,
        apiKey: String,
        provider: AIProvider,
        anthropicKey: String?
    ) async throws -> TranscriptionResult {
        try await SpeakerDiarization.identifySpeakers(
            transcript: transcript,
            apiKey: apiKey,
            provider: provider,
            anthropicKey: anthropicKey
        )
    }

    func findHighlights(
        transcript: TranscriptionResult,
        settings: AppSettings
    ) async throws -> AnalysisResult {
        try await HighlightDetector.findHighlights(
            transcript: transcript,
            settings: settings
        )
    }
}
