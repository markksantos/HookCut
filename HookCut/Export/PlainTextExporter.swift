import Foundation

/// Exports full transcript with highlighted sections marked inline
struct PlainTextExporter {

    func generate(analysis: AnalysisResult, transcript: TranscriptionResult?) throws -> Data {
        let highlights = analysis.approvedHighlights.sorted(by: { $0.startTime < $1.startTime })
        let speakerMap = Dictionary(uniqueKeysWithValues: analysis.speakers.map { ($0.id, $0.name) })

        var output = "HOOKCUT HIGHLIGHTS EXPORT\n"
        output += "========================\n"
        output += "Summary: \(analysis.episodeSummary)\n"
        output += "Total highlights: \(highlights.count)\n"
        output += "========================\n\n"

        if let transcript = transcript {
            output += buildAnnotatedTranscript(segments: transcript.segments, highlights: highlights, speakerMap: speakerMap)
        } else {
            output += buildHighlightList(highlights: highlights, speakerMap: speakerMap)
        }

        guard let data = output.data(using: .utf8) else {
            throw ExportError.xmlGenerationFailed("Failed to encode plain text as UTF-8")
        }
        return data
    }

    // MARK: - Transcript with inline highlight markers

    private func buildAnnotatedTranscript(
        segments: [TranscriptionSegment],
        highlights: [Highlight],
        speakerMap: [UUID: String]
    ) -> String {
        var result = ""
        var nextHighlightIdx = 0
        var currentHighlightIdx: Int? = nil

        for segment in segments {
            let speaker = segment.speaker ?? "Unknown"

            // Open a new highlight marker if this segment overlaps with the next unprocessed highlight
            if currentHighlightIdx == nil, nextHighlightIdx < highlights.count {
                let h = highlights[nextHighlightIdx]
                // Highlight overlaps this segment if it starts before the segment ends
                // and hasn't already ended before the segment starts
                if h.startTime < segment.end + 0.5 && h.endTime > segment.start - 0.5 {
                    let hSpeaker = speakerMap[h.speakerId] ?? "Unknown"
                    result += "\n[HIGHLIGHT START - \(h.type.displayName) (\(h.rating)/5) by \(hSpeaker)]\n"
                    currentHighlightIdx = nextHighlightIdx
                }
            }

            // Write the segment line
            result += "[\(speaker)] \(segment.text)\n"

            // Close the highlight if it ends within this segment
            if let idx = currentHighlightIdx {
                let h = highlights[idx]
                if h.endTime <= segment.end + 0.5 {
                    result += "[HIGHLIGHT END]\n\n"
                    currentHighlightIdx = nil
                    nextHighlightIdx = idx + 1
                }
            }
        }

        // Close any still-open highlight
        if currentHighlightIdx != nil {
            result += "[HIGHLIGHT END]\n"
        }

        return result
    }

    // MARK: - Highlight list (no transcript)

    private func buildHighlightList(highlights: [Highlight], speakerMap: [UUID: String]) -> String {
        var result = ""

        for highlight in highlights {
            let speaker = speakerMap[highlight.speakerId] ?? "Unknown"
            result += "[\(formatTime(highlight.startTime)) - \(formatTime(highlight.endTime))]\n"
            result += "Speaker: \(speaker)\n"
            result += "Type: \(highlight.type.displayName) | Rating: \(highlight.rating)/5\n"
            result += "Text: \(highlight.text)\n"
            if !highlight.context.isEmpty {
                result += "Context: \(highlight.context)\n"
            }
            result += "\n"
        }

        return result
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSec = Int(seconds)
        let ss = totalSec % 60
        let mm = (totalSec / 60) % 60
        let hh = totalSec / 3600
        let ms = Int((seconds - Double(totalSec)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hh, mm, ss, ms)
    }
}
