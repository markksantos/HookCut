import Foundation
import AVFoundation

/// Handles transcription via OpenAI Whisper API
struct WhisperService {

    enum WhisperError: LocalizedError {
        case invalidAPIKey
        case fileTooLarge(Int64)
        case apiError(Int, String)
        case decodingError(String)
        case networkError(String)
        case chunkingFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidAPIKey: return "Invalid or missing OpenAI API key."
            case .fileTooLarge(let size): return "Audio file too large (\(size / 1_000_000)MB). Chunking failed."
            case .apiError(let code, let msg): return "Whisper API error (\(code)): \(msg)"
            case .decodingError(let msg): return "Failed to decode Whisper response: \(msg)"
            case .networkError(let msg): return "Network error: \(msg)"
            case .chunkingFailed(let msg): return "Audio chunking failed: \(msg)"
            }
        }
    }

    private static let maxChunkSize: Int64 = 25 * 1_024 * 1_024
    private static let chunkOverlap: TimeInterval = 10.0

    /// Transcribe an audio file using the Whisper API
    static func transcribe(
        audioURL: URL,
        apiKey: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> TranscriptionResult {
        guard !apiKey.isEmpty else { throw WhisperError.invalidAPIKey }

        let fileSize = try audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0

        if fileSize <= maxChunkSize {
            progressHandler(0.1)
            let response = try await callWhisperAPI(fileURL: audioURL, apiKey: apiKey)
            progressHandler(1.0)
            return parseWhisperResponse(response)
        } else {
            return try await transcribeChunked(
                audioURL: audioURL,
                apiKey: apiKey,
                progressHandler: progressHandler
            )
        }
    }

    // MARK: - Single File Transcription

    private static func callWhisperAPI(
        fileURL: URL,
        apiKey: String,
        retryCount: Int = 0
    ) async throws -> WhisperVerboseResponse {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        let audioData = try Data(contentsOf: fileURL)
        request.httpBody = buildMultipartBody(
            boundary: boundary,
            audioData: audioData,
            fileName: fileURL.lastPathComponent
        )

        let (data, response) = try await APISession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 429, retryCount < 3 {
            let delay = UInt64(pow(2.0, Double(retryCount + 1))) * 1_000_000_000
            try await Task.sleep(nanoseconds: delay)
            return try await callWhisperAPI(fileURL: fileURL, apiKey: apiKey, retryCount: retryCount + 1)
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WhisperError.apiError(httpResponse.statusCode, errorBody)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(WhisperVerboseResponse.self, from: data)
        } catch {
            throw WhisperError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Chunked Transcription

    private static func transcribeChunked(
        audioURL: URL,
        apiKey: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> TranscriptionResult {
        let asset = AVAsset(url: audioURL)
        let durationCM = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(durationCM)

        let chunkDuration: TimeInterval = 20 * 60
        var chunks: [(start: TimeInterval, end: TimeInterval)] = []
        var chunkStart: TimeInterval = 0

        while chunkStart < totalDuration {
            let chunkEnd = min(chunkStart + chunkDuration, totalDuration)
            chunks.append((start: chunkStart, end: chunkEnd))
            chunkStart = chunkEnd - chunkOverlap
            if chunkEnd >= totalDuration { break }
        }

        var allSegments: [TranscriptionSegment] = []
        var allText = ""
        var language: String?

        for (index, chunk) in chunks.enumerated() {
            let chunkURL = try await exportChunk(from: audioURL, start: chunk.start, end: chunk.end)
            defer { try? FileManager.default.removeItem(at: chunkURL) }

            let response = try await callWhisperAPI(fileURL: chunkURL, apiKey: apiKey)
            let chunkResult = parseWhisperResponse(response, timeOffset: chunk.start)

            if index == 0 { language = chunkResult.language }

            if index > 0, let lastEnd = allSegments.last?.end {
                let newSegments = chunkResult.segments.filter { $0.start >= lastEnd - 1.0 }
                allSegments.append(contentsOf: newSegments)
            } else {
                allSegments.append(contentsOf: chunkResult.segments)
            }

            allText += (allText.isEmpty ? "" : " ") + chunkResult.fullText
            progressHandler(Double(index + 1) / Double(chunks.count))
        }

        return TranscriptionResult(
            segments: allSegments,
            fullText: allText.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: totalDuration,
            language: language
        )
    }

    private static func exportChunk(
        from audioURL: URL,
        start: TimeInterval,
        end: TimeInterval
    ) async throws -> URL {
        let asset = AVAsset(url: audioURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk_\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw WhisperError.chunkingFailed("Could not create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw WhisperError.chunkingFailed(exportSession.error?.localizedDescription ?? "Unknown")
        }
        return outputURL
    }

    // MARK: - Response Parsing

    private static func parseWhisperResponse(
        _ response: WhisperVerboseResponse,
        timeOffset: TimeInterval = 0
    ) -> TranscriptionResult {
        let segments = (response.segments ?? []).map { seg in
            let words = (seg.words ?? []).map { w in
                TranscriptionWord(
                    word: w.word,
                    start: w.start + timeOffset,
                    end: w.end + timeOffset
                )
            }
            return TranscriptionSegment(
                text: seg.text.trimmingCharacters(in: .whitespaces),
                start: seg.start + timeOffset,
                end: seg.end + timeOffset,
                words: words
            )
        }

        return TranscriptionResult(
            segments: segments,
            fullText: response.text,
            duration: response.duration ?? 0,
            language: response.language
        )
    }

    // MARK: - Multipart Form Data

    private static func buildMultipartBody(
        boundary: String,
        audioData: Data,
        fileName: String
    ) -> Data {
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", "whisper-1")
        appendField("response_format", "verbose_json")
        appendField("timestamp_granularities[]", "word")
        appendField("timestamp_granularities[]", "segment")

        let mimeType = fileName.hasSuffix(".wav") ? "audio/wav" : "audio/m4a"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }
}

// MARK: - Whisper API Response Models

struct WhisperVerboseResponse: Codable {
    let text: String
    let language: String?
    let duration: TimeInterval?
    let segments: [WhisperSegment]?
    let words: [WhisperWord]?
}

struct WhisperSegment: Codable {
    let id: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let words: [WhisperWord]?
}

struct WhisperWord: Codable {
    let word: String
    let start: TimeInterval
    let end: TimeInterval
}
