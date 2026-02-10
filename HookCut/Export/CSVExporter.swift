import Foundation

/// Exports highlights as a CSV file
struct CSVExporter {

    func generate(analysis: AnalysisResult, mediaFile: MediaFileInfo) throws -> Data {
        let clips = analysis.approvedHighlights.sorted(by: { $0.startTime < $1.startTime })
        guard !clips.isEmpty else {
            throw ExportError.noHighlights
        }

        let speakerMap = Dictionary(uniqueKeysWithValues: analysis.speakers.map { ($0.id, $0.name) })

        var lines: [String] = []
        lines.append("#,Speaker,Type,Rating,Start Time,End Time,Duration,Text,Context")

        for highlight in clips {
            let speaker = speakerMap[highlight.speakerId] ?? "Unknown"
            let fields: [String] = [
                String(highlight.sequenceNumber),
                csvEscape(speaker),
                csvEscape(highlight.type.displayName),
                String(highlight.rating),
                formatTime(highlight.startTime),
                formatTime(highlight.endTime),
                formatTime(highlight.duration),
                csvEscape(highlight.text),
                csvEscape(highlight.context)
            ]
            lines.append(fields.joined(separator: ","))
        }

        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw ExportError.xmlGenerationFailed("Failed to encode CSV as UTF-8")
        }
        return data
    }

    // MARK: - Helpers

    /// Format TimeInterval as HH:MM:SS.mmm
    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalMs = Int(round(seconds * 1000))
        let ms = totalMs % 1000
        let totalSec = totalMs / 1000
        let ss = totalSec % 60
        let mm = (totalSec / 60) % 60
        let hh = totalSec / 3600
        return String(format: "%02d:%02d:%02d.%03d", hh, mm, ss, ms)
    }

    /// Escape a field for CSV: wrap in quotes if it contains comma, quote, or newline
    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
