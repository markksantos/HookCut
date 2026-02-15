import Foundation

/// Detects highlights in a transcript using GPT-4o or Claude
struct HighlightDetector {

    enum DetectionError: LocalizedError {
        case noAPIKey
        case apiError(Int, String)
        case parsingFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key configured for highlight detection."
            case .apiError(let code, let msg): return "AI API error (\(code)): \(msg)"
            case .parsingFailed(let msg): return "Failed to parse highlight detection result: \(msg)"
            }
        }
    }

    /// Find highlights in a speaker-labeled transcript
    static func findHighlights(
        transcript: TranscriptionResult,
        settings: AppSettings,
        templateOverride: PromptTemplate? = nil
    ) async throws -> AnalysisResult {
        let systemPrompt = buildSystemPrompt(settings: settings, templateOverride: templateOverride)
        let userPrompt = buildUserPrompt(transcript: transcript)

        let responseJSON: String
        switch settings.aiProvider {
        case .openAI:
            guard !settings.openAIAPIKey.isEmpty else { throw DetectionError.noAPIKey }
            responseJSON = try await callOpenAI(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                apiKey: settings.openAIAPIKey
            )
        case .anthropic:
            if !settings.anthropicAPIKey.isEmpty {
                responseJSON = try await callAnthropic(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    apiKey: settings.anthropicAPIKey
                )
            } else {
                guard !settings.openAIAPIKey.isEmpty else { throw DetectionError.noAPIKey }
                responseJSON = try await callOpenAI(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    apiKey: settings.openAIAPIKey
                )
            }
        }

        return try parseResponse(responseJSON, transcript: transcript)
    }

    // MARK: - Prompt Building

    private static func buildSystemPrompt(
        settings: AppSettings,
        templateOverride: PromptTemplate?
    ) -> String {
        let enabledTypes = settings.enabledHighlightTypes.map(\.displayName).joined(separator: ", ")
        let count = settings.defaultHighlightCount

        let templateAddition = templateOverride?.systemPromptOverride ?? ""
        let customAddition = settings.customPromptAdditions

        return """
        You are an expert podcast editor. You're analyzing a transcript to find the absolute best moments \
        for a highlight reel / teaser intro.

        Find the best:
        - One-liners: punchy single sentences that stand alone as powerful statements
        - Cliffhangers: statements that create curiosity or tension ("and that's when everything changed")
        - Hot takes: controversial or surprising opinions that would make someone stop scrolling
        - Emotional moments: vulnerability, passion, strong conviction
        - Quotable insights: smart observations someone would screenshot and share
        - Humor: genuinely funny moments

        Rules:
        - Find \(count > 0 ? "\(count) highlights" : "as many highlights as you think are worthy — use your expert judgment based on episode length and content quality, roughly 1-2 per 5 minutes")
        - IMPORTANT: The total duration of ALL highlights combined should be approximately \(settings.targetDurationSeconds > 0 ? "\(settings.targetDurationSeconds) seconds" : "unconstrained"). Select highlights that when combined will fit this target duration. Prefer shorter, punchier clips if the target is short, and include more context if the target is longer.
        - Only include these types: \(enabledTypes)
        - NEVER cut a sentence in half — include the complete thought, even if it's 2-3 sentences
        - Include enough context so the clip makes sense on its own (may need the sentence before the key line)
        - Group highlights by speaker
        - For each highlight, rate it 1-5 stars (5 = absolute banger, must-use)
        - Include the exact word-for-word text as it appears in the transcript
        - Mark the start timestamp (slightly before the key moment for context) and end timestamp (when the thought completes, with a brief pause after)
        \(templateAddition.isEmpty ? "" : "\nTemplate instructions: \(templateAddition)")
        \(customAddition.isEmpty ? "" : "\nAdditional instructions: \(customAddition)")

        Return ONLY valid JSON in this exact format:
        {
          "episode_summary": "one paragraph summary",
          "speakers": [
            {
              "name": "Speaker Name",
              "role": "their role/title if mentioned",
              "highlights": [
                {
                  "id": 1,
                  "type": "one-liner",
                  "rating": 5,
                  "text": "exact quote",
                  "context": "brief context of what they're discussing",
                  "start_time": 267.5,
                  "end_time": 274.8
                }
              ]
            }
          ],
          "suggested_teaser_order": [3, 7, 1, 12, 5]
        }

        Valid types: one-liner, cliffhanger, hot-take, emotional, insight, humor
        The "suggested_teaser_order" is your recommended sequence of highlight IDs for a teaser intro, \
        ordered for maximum impact (start strong, build tension, end with the biggest hook).
        """
    }

    private static func buildUserPrompt(transcript: TranscriptionResult) -> String {
        var text = "Here is the full speaker-labeled transcript to analyze:\n\n"
        for segment in transcript.segments {
            let speaker = segment.speaker ?? "Unknown"
            let timeStr = String(format: "[%.1f-%.1f]", segment.start, segment.end)
            text += "\(timeStr) \(speaker): \(segment.text)\n"
        }
        text += "\nTotal duration: \(String(format: "%.0f", transcript.duration)) seconds"
        return text
    }

    // MARK: - OpenAI

    private static func callOpenAI(
        systemPrompt: String,
        userPrompt: String,
        apiKey: String,
        retryCount: Int = 0
    ) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3,
            "max_tokens": 8192,
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
            throw DetectionError.apiError(0, "Invalid response")
        }

        if httpResponse.statusCode == 429, retryCount < 3 {
            let delay = UInt64(pow(2.0, Double(retryCount + 1))) * 1_000_000_000
            try await Task.sleep(nanoseconds: delay)
            return try await callOpenAI(systemPrompt: systemPrompt, userPrompt: userPrompt, apiKey: apiKey, retryCount: retryCount + 1)
        }

        guard httpResponse.statusCode == 200 else {
            throw DetectionError.apiError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw DetectionError.parsingFailed("Could not extract content from OpenAI response")
        }
        return content
    }

    // MARK: - Anthropic

    private static func callAnthropic(
        systemPrompt: String,
        userPrompt: String,
        apiKey: String,
        retryCount: Int = 0
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-5-20250929",
            "max_tokens": 8192,
            "messages": [["role": "user", "content": userPrompt]],
            "system": systemPrompt
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
            throw DetectionError.apiError(0, "Invalid response")
        }

        if httpResponse.statusCode == 429, retryCount < 3 {
            let delay = UInt64(pow(2.0, Double(retryCount + 1))) * 1_000_000_000
            try await Task.sleep(nanoseconds: delay)
            return try await callAnthropic(systemPrompt: systemPrompt, userPrompt: userPrompt, apiKey: apiKey, retryCount: retryCount + 1)
        }

        guard httpResponse.statusCode == 200 else {
            throw DetectionError.apiError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw DetectionError.parsingFailed("Could not extract text from Anthropic response")
        }
        return text
    }

    // MARK: - Response Parsing

    private static func parseResponse(
        _ jsonString: String,
        transcript: TranscriptionResult
    ) throws -> AnalysisResult {
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DetectionError.parsingFailed("Invalid JSON in AI response")
        }

        let episodeSummary = json["episode_summary"] as? String ?? ""
        let suggestedOrder = json["suggested_teaser_order"] as? [Int] ?? []

        guard let speakersArray = json["speakers"] as? [[String: Any]] else {
            throw DetectionError.parsingFailed("Missing 'speakers' in response")
        }

        let speakerColors = [
            "#007AFF", "#FF3B30", "#34C759", "#FF9500", "#AF52DE",
            "#00C7BE", "#FF2D55", "#5856D6", "#FFCC00", "#64D2FF"
        ]

        var speakers: [Speaker] = []
        var allHighlights: [Highlight] = []
        var sequenceCounter = 1

        for (sIdx, speakerDict) in speakersArray.enumerated() {
            let name = speakerDict["name"] as? String ?? "Speaker \(sIdx + 1)"
            let role = speakerDict["role"] as? String
            let color = speakerColors[sIdx % speakerColors.count]
            let speaker = Speaker(name: name, role: role, color: color)
            speakers.append(speaker)

            let highlights = speakerDict["highlights"] as? [[String: Any]] ?? []
            for hDict in highlights {
                let typeStr = hDict["type"] as? String ?? "insight"
                let type = HighlightType(rawValue: typeStr) ?? .insight

                let rating: Int
                if let r = hDict["rating"] as? Int {
                    rating = max(1, min(5, r))
                } else if let r = hDict["rating"] as? Double {
                    rating = max(1, min(5, Int(r)))
                } else {
                    rating = 3
                }

                let startTime: TimeInterval
                if let t = hDict["start_time"] as? Double { startTime = t }
                else if let t = hDict["start_time"] as? Int { startTime = Double(t) }
                else { startTime = 0 }

                let endTime: TimeInterval
                if let t = hDict["end_time"] as? Double { endTime = t }
                else if let t = hDict["end_time"] as? Int { endTime = Double(t) }
                else { endTime = startTime + 5 }

                let highlight = Highlight(
                    sequenceNumber: sequenceCounter,
                    type: type,
                    rating: rating,
                    text: hDict["text"] as? String ?? "",
                    context: hDict["context"] as? String ?? "",
                    startTime: startTime,
                    endTime: endTime,
                    speakerId: speaker.id
                )
                allHighlights.append(highlight)
                sequenceCounter += 1
            }
        }

        return AnalysisResult(
            episodeSummary: episodeSummary,
            speakers: speakers,
            highlights: allHighlights,
            suggestedTeaserOrder: suggestedOrder
        )
    }
}
