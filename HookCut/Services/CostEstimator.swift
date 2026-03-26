import Foundation

/// Provides detailed API cost estimates before processing
struct CostEstimatorService {

    /// Whisper API cost: $0.006 per minute
    private static let whisperCostPerMinute = 0.006

    /// Approximate words per minute in spoken audio
    private static let wordsPerMinute = 150.0

    /// Approximate tokens per word (for English)
    private static let tokensPerWord = 1.33

    /// GPT-4o pricing per million tokens
    private static let gpt4oInputPricePerMillion = 2.50
    private static let gpt4oOutputPricePerMillion = 10.0

    /// Claude pricing per million tokens (approximate)
    private static let claudeInputPricePerMillion = 3.0
    private static let claudeOutputPricePerMillion = 15.0

    /// Estimated output tokens for diarization + highlight detection
    private static let estimatedOutputTokens = 3000.0

    /// Calculate a detailed cost estimate for processing a media file
    static func estimate(
        durationSeconds: TimeInterval,
        provider: AIProvider = .openAI
    ) -> DetailedCostEstimate {
        let minutes = durationSeconds / 60.0

        // Whisper transcription cost
        let whisperCost = minutes * whisperCostPerMinute

        // Estimate transcript token count
        let totalWords = minutes * wordsPerMinute
        let transcriptTokens = totalWords * tokensPerWord

        // Diarization: send transcript + prompt (~500 tokens) as input, ~2000 tokens output
        let diarizationInputTokens = transcriptTokens + 500
        let diarizationOutputTokens = 2000.0

        // Highlight detection: send transcript + system prompt (~1500 tokens) as input, ~3000 tokens output
        let highlightInputTokens = transcriptTokens + 1500
        let highlightOutputTokens = estimatedOutputTokens

        let totalInputTokens = diarizationInputTokens + highlightInputTokens
        let totalOutputTokens = diarizationOutputTokens + highlightOutputTokens

        let analysisCost: Double
        switch provider {
        case .openAI:
            analysisCost = (totalInputTokens / 1_000_000 * gpt4oInputPricePerMillion)
                         + (totalOutputTokens / 1_000_000 * gpt4oOutputPricePerMillion)
        case .anthropic:
            analysisCost = (totalInputTokens / 1_000_000 * claudeInputPricePerMillion)
                         + (totalOutputTokens / 1_000_000 * claudeOutputPricePerMillion)
        case .ollama:
            analysisCost = 0 // Local, free
        }

        return DetailedCostEstimate(
            whisperCost: whisperCost,
            diarizationCost: analysisCost * 0.4,  // rough split
            highlightCost: analysisCost * 0.6,
            totalCost: whisperCost + analysisCost,
            audioDurationMinutes: minutes,
            estimatedTranscriptTokens: Int(transcriptTokens),
            estimatedTotalInputTokens: Int(totalInputTokens),
            estimatedTotalOutputTokens: Int(totalOutputTokens)
        )
    }
}

struct DetailedCostEstimate {
    let whisperCost: Double
    let diarizationCost: Double
    let highlightCost: Double
    let totalCost: Double
    let audioDurationMinutes: Double
    let estimatedTranscriptTokens: Int
    let estimatedTotalInputTokens: Int
    let estimatedTotalOutputTokens: Int

    var formattedTotal: String {
        String(format: "$%.2f", totalCost)
    }

    var breakdown: String {
        String(format: "Transcription: $%.3f | Analysis: $%.3f", whisperCost, diarizationCost + highlightCost)
    }
}
