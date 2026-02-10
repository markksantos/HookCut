import Foundation

/// Generates valid FCPXML v1.11 for Final Cut Pro import
struct FCPXMLGenerator {

    func generate(analysis: AnalysisResult, mediaFile: MediaFileInfo, config: ExportConfig) throws -> Data {
        let frameRate = mediaFile.frameRate ?? .fps30
        let clips = analysis.approvedHighlights.sorted(by: { $0.startTime < $1.startTime })
        guard !clips.isEmpty else {
            throw ExportError.noHighlights
        }

        let root = XMLElement(name: "fcpxml")
        root.addAttribute(XMLNode.attribute(withName: "version", stringValue: "1.11") as! XMLNode)

        // Resources
        let resources = XMLElement(name: "resources")
        let formatId = "r1"
        let assetId = "r2"

        let formatEl = XMLElement(name: "format")
        formatEl.addAttribute(attr("id", formatId))
        formatEl.addAttribute(attr("frameDuration", frameRate.frameDuration.fcpxmlString))
        formatEl.addAttribute(attr("width", String(mediaFile.videoWidth ?? 1920)))
        formatEl.addAttribute(attr("height", String(mediaFile.videoHeight ?? 1080)))
        resources.addChild(formatEl)

        let totalDuration = RationalTime.fromSeconds(mediaFile.duration, frameRate: frameRate)
        let assetEl = XMLElement(name: "asset")
        assetEl.addAttribute(attr("id", assetId))
        assetEl.addAttribute(attr("src", mediaFile.url.absoluteString))
        assetEl.addAttribute(attr("start", "0s"))
        assetEl.addAttribute(attr("duration", totalDuration.fcpxmlString))
        assetEl.addAttribute(attr("hasVideo", mediaFile.isVideoFile ? "1" : "0"))
        assetEl.addAttribute(attr("hasAudio", "1"))
        assetEl.addAttribute(attr("format", formatId))
        resources.addChild(assetEl)

        root.addChild(resources)

        // Library → Event → Project → Sequence → Spine
        let library = XMLElement(name: "library")
        let eventName = "HookCut - \(config.projectName)"
        let event = XMLElement(name: "event")
        event.addAttribute(attr("name", eventName))

        let project = XMLElement(name: "project")
        project.addAttribute(attr("name", "Highlights - \(config.projectName)"))

        // Calculate total sequence duration: sum of clip durations + gaps between them
        let gapTime = RationalTime.fromSeconds(config.gapDuration, frameRate: frameRate)
        let totalSequenceDuration = sequenceDuration(clips: clips, gapTime: gapTime, frameRate: frameRate)

        let sequence = XMLElement(name: "sequence")
        sequence.addAttribute(attr("format", formatId))
        sequence.addAttribute(attr("duration", totalSequenceDuration.fcpxmlString))
        sequence.addAttribute(attr("tcStart", "0s"))
        sequence.addAttribute(attr("tcFormat", frameRate.isDropFrame ? "DF" : "NDF"))

        let spine = XMLElement(name: "spine")

        var runningOffset = RationalTime(numerator: 0, denominator: frameRate.frameDuration.denominator)

        for (index, highlight) in clips.enumerated() {
            let clipStart = RationalTime.fromSeconds(highlight.startTime, frameRate: frameRate)
            let clipDuration = RationalTime.fromSeconds(highlight.duration, frameRate: frameRate)

            let clipName = sanitizeForXML("\(highlight.type.displayName): \(highlight.text)")
            let assetClip = XMLElement(name: "asset-clip")
            assetClip.addAttribute(attr("ref", assetId))
            assetClip.addAttribute(attr("offset", runningOffset.fcpxmlString))
            assetClip.addAttribute(attr("start", clipStart.fcpxmlString))
            assetClip.addAttribute(attr("duration", clipDuration.fcpxmlString))
            assetClip.addAttribute(attr("name", clipName))

            if config.includeMarkers {
                let marker = XMLElement(name: "marker")
                marker.addAttribute(attr("start", clipStart.fcpxmlString))
                marker.addAttribute(attr("value", sanitizeForXML("\(highlight.type.displayName): \(highlight.text)")))
                assetClip.addChild(marker)
            }

            spine.addChild(assetClip)

            // Advance running offset by clip duration
            runningOffset = addRationalTimes(runningOffset, clipDuration, denominator: frameRate.frameDuration.denominator)

            // Add gap between clips (except after the last one)
            if index < clips.count - 1 {
                let gap = XMLElement(name: "gap")
                gap.addAttribute(attr("offset", runningOffset.fcpxmlString))
                gap.addAttribute(attr("duration", gapTime.fcpxmlString))
                spine.addChild(gap)

                runningOffset = addRationalTimes(runningOffset, gapTime, denominator: frameRate.frameDuration.denominator)
            }
        }

        sequence.addChild(spine)
        project.addChild(sequence)
        event.addChild(project)
        library.addChild(event)
        root.addChild(library)

        let xmlDoc = XMLDocument(rootElement: root)
        xmlDoc.version = "1.0"
        xmlDoc.characterEncoding = "UTF-8"
        xmlDoc.dtd = XMLDTD()
        xmlDoc.dtd!.name = "fcpxml"

        let xmlData = xmlDoc.xmlData(options: [.nodePrettyPrint])
        // Validate well-formedness by re-parsing
        _ = try XMLDocument(data: xmlData)
        return xmlData
    }

    // MARK: - Helpers

    private func attr(_ name: String, _ value: String) -> XMLNode {
        XMLNode.attribute(withName: name, stringValue: value) as! XMLNode
    }

    private func sanitizeForXML(_ string: String) -> String {
        // XMLElement handles escaping automatically, but truncate overly long names
        let maxLength = 200
        if string.count > maxLength {
            return String(string.prefix(maxLength)) + "..."
        }
        return string
    }

    private func addRationalTimes(_ a: RationalTime, _ b: RationalTime, denominator: Int) -> RationalTime {
        // Both times share the same denominator (from the same frame rate)
        if a.denominator == b.denominator {
            return RationalTime(numerator: a.numerator + b.numerator, denominator: a.denominator)
        }
        // Cross-multiply for different denominators
        let commonDenom = a.denominator * b.denominator
        let newNum = a.numerator * b.denominator + b.numerator * a.denominator
        return RationalTime(numerator: newNum, denominator: commonDenom)
    }

    private func sequenceDuration(clips: [Highlight], gapTime: RationalTime, frameRate: FrameRate) -> RationalTime {
        let denom = frameRate.frameDuration.denominator
        var totalNumerator = 0

        for (index, highlight) in clips.enumerated() {
            let clipDuration = RationalTime.fromSeconds(highlight.duration, frameRate: frameRate)
            // Ensure same denominator for accumulation
            if clipDuration.denominator == denom {
                totalNumerator += clipDuration.numerator
            } else {
                totalNumerator += clipDuration.numerator * denom / clipDuration.denominator
            }

            if index < clips.count - 1 {
                if gapTime.denominator == denom {
                    totalNumerator += gapTime.numerator
                } else {
                    totalNumerator += gapTime.numerator * denom / gapTime.denominator
                }
            }
        }

        return RationalTime(numerator: totalNumerator, denominator: denom)
    }
}

// MARK: - Export Errors

enum ExportError: LocalizedError {
    case noHighlights
    case xmlGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noHighlights:
            return "No approved highlights to export."
        case .xmlGenerationFailed(let detail):
            return "XML generation failed: \(detail)"
        }
    }
}
