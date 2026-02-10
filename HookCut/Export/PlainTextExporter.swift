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
            // Full transcript with highlight markers
            output += buildAnnotatedTranscript(segments: transcript.segments, highlights: highlights, speakerMap: speakerMap)
        } else {
            // No transcript available; list highlights only
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
        var highlightIndex = 0
        var insideHighlight = false

        for segment in segments {
            let speaker = segment.speaker ?? "Unknown"
            let segStart = segment.start
            let segEnd = segment.end

            // Check if a highlight starts at or before this segment
            while highlightIndex < highlights.count {
                let h = highlights[highlightIndex]

                if !insideHighlight && h.startTime <= segStart {
                    let hSpeaker = speakerMap[h.speakerId] ?? "Unknown"
                    result += "[HIGHLIGHT START - \(h.type.displayName) (\(h.rating)/5) by \(hSpeaker)]\n"
                    insideHighlight = true
                }

                if insideHighlight && h.endTime <= segEnd {
                    // This highlight ends within or at this segment
                    result += "[\(speaker)] \(segment.text)\n"
                    result += "[HIGHLIGHT END]\n\n"
                    insideHighlight = false
                    highlightIndex += 1
                    continue
                }

                break
            }

            if !insideHighlight || (insideHighlight && highlightIndex < highlights.count && highlights[highlightIndex].endTime > segEnd) {
                result += "[\(speaker)] \(segment.text)\n"
            }
        }

        // Close any still-open highlight
        if insideHighlight {
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
