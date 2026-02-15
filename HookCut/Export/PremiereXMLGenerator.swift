import Foundation

/// Generates Adobe Premiere Pro compatible XML (FCP 7 XML interchange format)
struct PremiereXMLGenerator {

    func generate(analysis: AnalysisResult, mediaFile: MediaFileInfo, config: ExportConfig) throws -> Data {
        let frameRate = mediaFile.frameRate ?? .fps30
        let clips = analysis.approvedHighlights.sorted(by: { $0.startTime < $1.startTime })
        guard !clips.isEmpty else {
            throw ExportError.noHighlights
        }

        let timebase = Int(round(frameRate.fps))
        let isNTSC = frameRate.isDropFrame

        let root = XMLElement(name: "xmeml")
        root.addAttribute(XMLNode.attribute(withName: "version", stringValue: "5") as! XMLNode)

        let sequence = XMLElement(name: "sequence")
        addElement(to: sequence, name: "name", value: "Highlights - \(config.projectName)")
        addElement(to: sequence, name: "duration", value: String(totalFrames(clips: clips, gapDuration: config.gapDuration, fps: frameRate.fps)))

        // Rate
        let rate = XMLElement(name: "rate")
        addElement(to: rate, name: "timebase", value: String(timebase))
        addElement(to: rate, name: "ntsc", value: isNTSC ? "TRUE" : "FALSE")
        sequence.addChild(rate)

        // Timecode
        let timecode = XMLElement(name: "timecode")
        let tcRate = XMLElement(name: "rate")
        addElement(to: tcRate, name: "timebase", value: String(timebase))
        addElement(to: tcRate, name: "ntsc", value: isNTSC ? "TRUE" : "FALSE")
        timecode.addChild(tcRate)
        addElement(to: timecode, name: "string", value: "00:00:00:00")
        addElement(to: timecode, name: "frame", value: "0")
        addElement(to: timecode, name: "displayformat", value: isNTSC ? "DF" : "NDF")
        sequence.addChild(timecode)

        // Media → video → track
        let media = XMLElement(name: "media")
        let video = XMLElement(name: "video")
        let videoTrack = XMLElement(name: "track")

        // Media → audio → track
        let audio = XMLElement(name: "audio")
        let audioTrack = XMLElement(name: "track")

        var recStart = 0 // running frame position on timeline

        for (index, highlight) in clips.enumerated() {
            let srcInFrames = secondsToFrames(highlight.startTime, fps: frameRate.fps)
            let srcOutFrames = secondsToFrames(highlight.endTime, fps: frameRate.fps)
            let durationFrames = srcOutFrames - srcInFrames
            let recEnd = recStart + durationFrames

            let videoClip = buildClipItem(
                name: sanitize("\(highlight.type.displayName): \(highlight.text)"),
                srcIn: srcInFrames,
                srcOut: srcOutFrames,
                recIn: recStart,
                recOut: recEnd,
                filePath: mediaFile.url.absoluteString,
                fileName: mediaFile.fileName,
                timebase: timebase,
                isNTSC: isNTSC,
                mediaType: "video",
                width: mediaFile.videoWidth ?? 1920,
                height: mediaFile.videoHeight ?? 1080
            )
            videoTrack.addChild(videoClip)

            let audioClip = buildClipItem(
                name: sanitize("\(highlight.type.displayName): \(highlight.text)"),
                srcIn: srcInFrames,
                srcOut: srcOutFrames,
                recIn: recStart,
                recOut: recEnd,
                filePath: mediaFile.url.absoluteString,
                fileName: mediaFile.fileName,
                timebase: timebase,
                isNTSC: isNTSC,
                mediaType: "audio",
                width: mediaFile.videoWidth ?? 1920,
                height: mediaFile.videoHeight ?? 1080
            )
            audioTrack.addChild(audioClip)

            recStart = recEnd

            // Add gap between clips (except after last)
            if index < clips.count - 1 {
                let gapFrames = secondsToFrames(config.gapDuration, fps: frameRate.fps)
                recStart += gapFrames
            }
        }

        video.addChild(videoTrack)
        audio.addChild(audioTrack)
        media.addChild(video)
        media.addChild(audio)
        sequence.addChild(media)
        root.addChild(sequence)

        let xmlDoc = XMLDocument(rootElement: root)
        xmlDoc.version = "1.0"
        xmlDoc.characterEncoding = "UTF-8"

        return xmlDoc.xmlData(options: [.nodePrettyPrint])
    }

    // MARK: - Helpers

    private func buildClipItem(
        name: String, srcIn: Int, srcOut: Int, recIn: Int, recOut: Int,
        filePath: String, fileName: String, timebase: Int, isNTSC: Bool,
        mediaType: String, width: Int, height: Int
    ) -> XMLElement {
        let clipItem = XMLElement(name: "clipitem")
        addElement(to: clipItem, name: "name", value: name)
        addElement(to: clipItem, name: "duration", value: String(srcOut - srcIn))

        let rate = XMLElement(name: "rate")
        addElement(to: rate, name: "timebase", value: String(timebase))
        addElement(to: rate, name: "ntsc", value: isNTSC ? "TRUE" : "FALSE")
        clipItem.addChild(rate)

        addElement(to: clipItem, name: "in", value: String(srcIn))
        addElement(to: clipItem, name: "out", value: String(srcOut))
        addElement(to: clipItem, name: "start", value: String(recIn))
        addElement(to: clipItem, name: "end", value: String(recOut))

        // File reference
        let file = XMLElement(name: "file")
        file.addAttribute(XMLNode.attribute(withName: "id", stringValue: "file-1") as! XMLNode)
        addElement(to: file, name: "name", value: fileName)
        addElement(to: file, name: "pathurl", value: filePath)

        let fileRate = XMLElement(name: "rate")
        addElement(to: fileRate, name: "timebase", value: String(timebase))
        addElement(to: fileRate, name: "ntsc", value: isNTSC ? "TRUE" : "FALSE")
        file.addChild(fileRate)

        let fileMedia = XMLElement(name: "media")
        if mediaType == "video" {
            let v = XMLElement(name: "video")
            let sc = XMLElement(name: "samplecharacteristics")
            addElement(to: sc, name: "width", value: String(width))
            addElement(to: sc, name: "height", value: String(height))
            v.addChild(sc)
            fileMedia.addChild(v)
        } else {
            let a = XMLElement(name: "audio")
            fileMedia.addChild(a)
        }
        file.addChild(fileMedia)
        clipItem.addChild(file)

        return clipItem
    }

    private func addElement(to parent: XMLElement, name: String, value: String) {
        let el = XMLElement(name: name, stringValue: value)
        parent.addChild(el)
    }

    private func secondsToFrames(_ seconds: TimeInterval, fps: Double) -> Int {
        Int(round(seconds * fps))
    }

    private func totalFrames(clips: [Highlight], gapDuration: TimeInterval, fps: Double) -> Int {
        var total = 0
        for (index, clip) in clips.enumerated() {
            total += secondsToFrames(clip.duration, fps: fps)
            if index < clips.count - 1 {
                total += secondsToFrames(gapDuration, fps: fps)
            }
        }
        return total
    }

    private func sanitize(_ string: String) -> String {
        var s = string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
        let maxLength = 200
        if s.count > maxLength {
            s = String(s.prefix(maxLength)) + "..."
        }
        return s
    }
}
