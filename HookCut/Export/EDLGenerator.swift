import Foundation

/// Generates CMX 3600 EDL format for DaVinci Resolve and other NLEs
struct EDLGenerator {

    func generate(analysis: AnalysisResult, mediaFile: MediaFileInfo, config: ExportConfig) throws -> Data {
        let frameRate = mediaFile.frameRate ?? .fps30
        let clips = analysis.approvedHighlights.sorted(by: { $0.startTime < $1.startTime })
        guard !clips.isEmpty else {
            throw ExportError.noHighlights
        }

        let fps = frameRate.fps
        let isDropFrame = frameRate.isDropFrame

        var lines: [String] = []
        lines.append("TITLE: Highlights - \(config.projectName)")
        lines.append("FCM: \(isDropFrame ? "DROP FRAME" : "NON-DROP FRAME")")
        lines.append("")

        var recRunning: Double = 0.0

        for (index, highlight) in clips.enumerated() {
            let eventNum = String(format: "%03d", index + 1)
            let reelName = "AX"
            let editType = "V"
            let transition = "C"

            let srcIn = formatTimecode(highlight.startTime, fps: fps, dropFrame: isDropFrame)
            let srcOut = formatTimecode(highlight.endTime, fps: fps, dropFrame: isDropFrame)
            let recIn = formatTimecode(recRunning, fps: fps, dropFrame: isDropFrame)
            let recOut = formatTimecode(recRunning + highlight.duration, fps: fps, dropFrame: isDropFrame)

            // Standard EDL event line
            lines.append("\(eventNum)  \(reelName)       \(editType)     \(transition)        \(srcIn) \(srcOut) \(recIn) \(recOut)")

            // Comment with highlight info
            lines.append("* FROM CLIP NAME: \(mediaFile.fileName)")
            lines.append("* COMMENT: \(highlight.type.displayName) - \(highlight.text)")
            lines.append("")

            recRunning += highlight.duration
            if index < clips.count - 1 {
                recRunning += config.gapDuration
            }
        }

        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw ExportError.xmlGenerationFailed("Failed to encode EDL as UTF-8")
        }
        return data
    }

    // MARK: - Timecode Formatting

    /// Format seconds as timecode HH:MM:SS:FF (NDF) or HH:MM:SS;FF (DF)
    private func formatTimecode(_ totalSeconds: TimeInterval, fps: Double, dropFrame: Bool) -> String {
        let totalFrames = Int(round(totalSeconds * fps))
        let separator = dropFrame ? ";" : ":"

        let framesPerSecond = Int(round(fps))
        let ff = totalFrames % framesPerSecond
        let totalSecondsInt = totalFrames / framesPerSecond
        let ss = totalSecondsInt % 60
        let mm = (totalSecondsInt / 60) % 60
        let hh = totalSecondsInt / 3600

        return String(format: "%02d:%02d:%02d%@%02d", hh, mm, ss, separator, ff)
    }
}
