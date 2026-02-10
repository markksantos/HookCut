import Foundation

/// Generates SRT subtitle files from highlights
struct SRTExporter {

    func generate(analysis: AnalysisResult) throws -> Data {
        let clips = analysis.approvedHighlights.sorted(by: { $0.startTime < $1.startTime })
        guard !clips.isEmpty else {
            throw ExportError.noHighlights
        }

        var lines: [String] = []

        for (index, highlight) in clips.enumerated() {
            // Sequence number (1-based)
            lines.append(String(index + 1))
            // Timecode range: HH:MM:SS,mmm --> HH:MM:SS,mmm
            let startTC = formatSRTTime(highlight.startTime)
            let endTC = formatSRTTime(highlight.endTime)
            lines.append("\(startTC) --> \(endTC)")
            // Text
            lines.append(highlight.text)
            // Blank line separator
            lines.append("")
        }

        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw ExportError.xmlGenerationFailed("Failed to encode SRT as UTF-8")
        }
        return data
    }

    // MARK: - Helpers

    /// Format TimeInterval as HH:MM:SS,mmm (SRT uses comma for ms separator)
    private func formatSRTTime(_ seconds: TimeInterval) -> String {
        let totalMs = Int(round(seconds * 1000))
        let ms = totalMs % 1000
        let totalSec = totalMs / 1000
        let ss = totalSec % 60
        let mm = (totalSec / 60) % 60
        let hh = totalSec / 3600
        return String(format: "%02d:%02d:%02d,%03d", hh, mm, ss, ms)
    }
}
