import Foundation

/// Identifies speakers in a transcript using AI (GPT-4o or Claude)
struct SpeakerDiarization {

    enum DiarizationError: LocalizedError {
        case noAPIKey
        case apiError(Int, String)
        case parsingFailed(String)
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key configured for speaker identification."
            case .apiError(let code, let msg): return "AI API error (\(code)): \(msg)"
            case .parsingFailed(let msg): return "Failed to parse speaker identification result: \(msg)"
            case .networkError(let msg): return "Network error during speaker identification: \(msg)"
            }
        }
    }

    private static let speakerColors = [
        "#007AFF", "#FF3B30", "#34C759", "#FF9500", "#AF52DE",
        "#00C7BE", "#FF2D55", "#5856D6", "#FFCC00", "#64D2FF"
    ]

    /// Identify speakers and return updated transcript with speaker labels
    static func identifySpeakers(
        transcript: TranscriptionResult,
        apiKey: String,
        provider: AIProvider,
        anthropicKey: String?
    ) async throws -> TranscriptionResult {
        let prompt = buildDiarizationPrompt(transcript: transcript)

        let responseJSON: String
        switch provider {
        case .openAI:
            guard !apiKey.isEmpty else { throw DiarizationError.noAPIKey }
            responseJSON = try await callOpenAI(prompt: prompt, apiKey: apiKey)
        case .anthropic:
            if let key = anthropicKey, !key.isEmpty {
                responseJSON = try await callAnthropic(prompt: prompt, apiKey: key)
            } else {
                guard !apiKey.isEmpty else { throw DiarizationError.noAPIKey }
                responseJSON = try await callOpenAI(prompt: prompt, apiKey: apiKey)
            }
        }

        return try parseResponse(responseJSON, transcript: transcript)
    }

    // MARK: - Prompt

    private static func buildDiarizationPrompt(transcript: TranscriptionResult) -> String {
        var segmentList = ""
        for (i, segment) in transcript.segments.enumerated() {
            let timeStr = String(format: "[%.1f-%.1f]", segment.start, segment.end)
            segmentList += "Segment \(i): \(timeStr) \(segment.text)\n"
        }

        return """
        This is a podcast/interview transcript with multiple speakers. Based on context clues \
        (introductions, "thank you [name]", topic switches, speaking patterns, question-answer flow), \
        identify each unique speaker and label every segment with the speaker name.

        If speaker names are mentioned in the content, use those names. If not, use "Speaker 1", "Speaker 2", etc.
        Also identify their role if mentioned (host, guest, interviewer, etc.).

        Transcript segments:
        \(segmentList)

        Return ONLY valid JSON in this exact format, no other text:
        {
          "speakers": [
            {"name": "Speaker Name", "role": "host"}
          ],
          "segments": [
            {"index": 0, "speaker": "Speaker Name"},
            {"index": 1, "speaker": "Speaker Name"}
          ]
        }
        """
    }

    // MARK: - OpenAI

    private static func callOpenAI(prompt: String, apiKey: String, retryCount: Int = 0) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "You are an expert at identifying speakers in transcripts. Return only valid JSON."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await APISession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiarizationError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 429, retryCount < 3 {
            let delay = UInt64(pow(2.0, Double(retryCount + 1))) * 1_000_000_000
            try await Task.sleep(nanoseconds: delay)
            return try await callOpenAI(prompt: prompt, apiKey: apiKey, retryCount: retryCount + 1)
        }

        guard httpResponse.statusCode == 200 else {
            throw DiarizationError.apiError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw DiarizationError.parsingFailed("Could not extract content from OpenAI response")
        }
        return content
    }

    // MARK: - Anthropic

    private static func callAnthropic(prompt: String, apiKey: String, retryCount: Int = 0) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-5-20250929",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]],
            "system": "You are an expert at identifying speakers in transcripts. Return only valid JSON."
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await APISession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiarizationError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 429, retryCount < 3 {
            let delay = UInt64(pow(2.0, Double(retryCount + 1))) * 1_000_000_000
            try await Task.sleep(nanoseconds: delay)
            return try await callAnthropic(prompt: prompt, apiKey: apiKey, retryCount: retryCount + 1)
        }

        guard httpResponse.statusCode == 200 else {
            throw DiarizationError.apiError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw DiarizationError.parsingFailed("Could not extract text from Anthropic response")
        }
        return text
    }

    // MARK: - Parsing

    private static func parseResponse(
        _ jsonString: String,
        transcript: TranscriptionResult
    ) throws -> TranscriptionResult {
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DiarizationError.parsingFailed("Invalid JSON from AI response")
        }

        guard let segmentAssignments = json["segments"] as? [[String: Any]] else {
            throw DiarizationError.parsingFailed("Missing 'segments' in response")
        }

        var speakerMap: [Int: String] = [:]
        for assignment in segmentAssignments {
            if let index = assignment["index"] as? Int,
               let speaker = assignment["speaker"] as? String {
                speakerMap[index] = speaker
            }
        }

        var updatedSegments = transcript.segments
        for i in updatedSegments.indices {
            if let speaker = speakerMap[i] {
                updatedSegments[i].speaker = speaker
            }
        }

        return TranscriptionResult(
            segments: updatedSegments,
            fullText: transcript.fullText,
            duration: transcript.duration,
            language: transcript.language
        )
    }

    /// Extract unique Speaker objects from a diarized transcript
    static func extractSpeakers(from transcript: TranscriptionResult) -> [Speaker] {
        var seen: [String: Int] = [:]
        var speakers: [Speaker] = []
        for segment in transcript.segments {
            guard let name = segment.speaker, !name.isEmpty else { continue }
            if seen[name] == nil {
                let color = speakerColors[speakers.count % speakerColors.count]
                speakers.append(Speaker(name: name, color: color))
                seen[name] = speakers.count - 1
            }
        }
        return speakers
    }
}
