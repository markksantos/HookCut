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

        let width = mediaFile.videoWidth ?? 1920
        let height = mediaFile.videoHeight ?? 1080

        let formatEl = XMLElement(name: "format")
        formatEl.addAttribute(attr("id", formatId))
        formatEl.addAttribute(attr("name", fcpFormatName(width: width, height: height, frameRate: frameRate)))
        formatEl.addAttribute(attr("frameDuration", frameRate.frameDuration.fcpxmlString))
        formatEl.addAttribute(attr("width", String(width)))
        formatEl.addAttribute(attr("height", String(height)))
        resources.addChild(formatEl)

        let totalDuration = RationalTime.fromSeconds(mediaFile.duration, frameRate: frameRate)
        let assetEl = XMLElement(name: "asset")
        assetEl.addAttribute(attr("id", assetId))
        assetEl.addAttribute(attr("name", mediaFile.fileName))
        assetEl.addAttribute(attr("start", "0s"))
        assetEl.addAttribute(attr("duration", totalDuration.fcpxmlString))
        assetEl.addAttribute(attr("hasVideo", mediaFile.isVideoFile ? "1" : "0"))
        assetEl.addAttribute(attr("hasAudio", "1"))
        assetEl.addAttribute(attr("format", formatId))

        let mediaRep = XMLElement(name: "media-rep")
        mediaRep.addAttribute(attr("kind", "original-media"))
        mediaRep.addAttribute(attr("src", mediaFile.url.absoluteString))
        assetEl.addChild(mediaRep)

        resources.addChild(assetEl)
        root.addChild(resources)

        // Library → Event → Project → Sequence → Spine
        let library = XMLElement(name: "library")
        let eventName = "HookCut - \(config.projectName)"
        let event = XMLElement(name: "event")
        event.addAttribute(attr("name", eventName))

        let project = XMLElement(name: "project")
        project.addAttribute(attr("name", "Highlights - \(config.projectName)"))

        // Handle duration is used as padding on each clip (half before, half after)
        let handlePadding = config.gapDuration / 2.0

        let totalSequenceDuration = sequenceDuration(
            clips: clips,
            handlePadding: handlePadding,
            mediaDuration: mediaFile.duration,
            frameRate: frameRate
        )

        let sequence = XMLElement(name: "sequence")
        sequence.addAttribute(attr("duration", totalSequenceDuration.fcpxmlString))
        sequence.addAttribute(attr("format", formatId))
        sequence.addAttribute(attr("tcStart", "0s"))
        sequence.addAttribute(attr("tcFormat", "NDF"))

        let spine = XMLElement(name: "spine")

        var runningOffset = RationalTime(numerator: 0, denominator: frameRate.frameDuration.denominator)

        for highlight in clips {
            // Extend clip with handle padding for editor breathing room
            let paddedStart = max(0, highlight.startTime - handlePadding)
            let paddedEnd = min(mediaFile.duration, highlight.endTime + handlePadding)
            let paddedDuration = paddedEnd - paddedStart

            let clipStart = RationalTime.fromSeconds(paddedStart, frameRate: frameRate)
            let clipDuration = RationalTime.fromSeconds(paddedDuration, frameRate: frameRate)

            let clipName = sanitizeForXML("\(highlight.type.displayName): \(highlight.text)")
            let assetClip = XMLElement(name: "asset-clip")
            assetClip.addAttribute(attr("ref", assetId))
            assetClip.addAttribute(attr("offset", runningOffset.fcpxmlString))
            assetClip.addAttribute(attr("start", clipStart.fcpxmlString))
            assetClip.addAttribute(attr("duration", clipDuration.fcpxmlString))
            assetClip.addAttribute(attr("name", clipName))
            assetClip.addAttribute(attr("tcFormat", "NDF"))

            if config.includeMarkers {
                // Marker start is relative to the clip's own start point
                let markerOffset = RationalTime.fromSeconds(handlePadding, frameRate: frameRate)
                let markerStart = addRationalTimes(clipStart, markerOffset, denominator: frameRate.frameDuration.denominator)
                let marker = XMLElement(name: "marker")
                marker.addAttribute(attr("start", markerStart.fcpxmlString))
                marker.addAttribute(attr("value", sanitizeForXML("\(highlight.type.displayName): \(highlight.text)")))
                assetClip.addChild(marker)
            }

            spine.addChild(assetClip)

            // Advance running offset — clips placed back-to-back, no empty gaps
            runningOffset = addRationalTimes(runningOffset, clipDuration, denominator: frameRate.frameDuration.denominator)
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
        _ = try XMLDocument(data: xmlData)
        return xmlData
    }

    // MARK: - FCP Format Name

    /// Generate the FCP-recognized format name (e.g., "FFVideoFormat1080p2997")
    private func fcpFormatName(width: Int, height: Int, frameRate: FrameRate) -> String {
        let resolution: String
        switch height {
        case 0..<600: resolution = "\(height)p"
        case 600..<800: resolution = "720p"
        case 800..<1200: resolution = "1080p"
        case 1200..<1800: resolution = "1440p"
        case 1800..<2400: resolution = "2160p"
        default: resolution = "\(height)p"
        }

        let fps: String
        switch frameRate {
        case .fps23_976: fps = "2398"
        case .fps24: fps = "24"
        case .fps25: fps = "25"
        case .fps29_97: fps = "2997"
        case .fps30: fps = "30"
        case .fps59_94: fps = "5994"
        case .fps60: fps = "60"
        }

        return "FFVideoFormat\(resolution)\(fps)"
    }

    // MARK: - Helpers

    private func attr(_ name: String, _ value: String) -> XMLNode {
        XMLNode.attribute(withName: name, stringValue: value) as! XMLNode
    }

    private func sanitizeForXML(_ string: String) -> String {
        let maxLength = 200
        if string.count > maxLength {
            return String(string.prefix(maxLength)) + "..."
        }
        return string
    }

    private func addRationalTimes(_ a: RationalTime, _ b: RationalTime, denominator: Int) -> RationalTime {
        if a.denominator == b.denominator {
            return RationalTime(numerator: a.numerator + b.numerator, denominator: a.denominator)
        }
        let commonDenom = a.denominator * b.denominator
        let newNum = a.numerator * b.denominator + b.numerator * a.denominator
        return RationalTime(numerator: newNum, denominator: commonDenom)
    }

    private func sequenceDuration(
        clips: [Highlight],
        handlePadding: TimeInterval,
        mediaDuration: TimeInterval,
        frameRate: FrameRate
    ) -> RationalTime {
        let denom = frameRate.frameDuration.denominator
        var totalNumerator = 0

        for highlight in clips {
            let paddedStart = max(0, highlight.startTime - handlePadding)
            let paddedEnd = min(mediaDuration, highlight.endTime + handlePadding)
            let paddedDuration = paddedEnd - paddedStart

            let clipDuration = RationalTime.fromSeconds(paddedDuration, frameRate: frameRate)
            if clipDuration.denominator == denom {
                totalNumerator += clipDuration.numerator
            } else {
                totalNumerator += clipDuration.numerator * denom / clipDuration.denominator
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
