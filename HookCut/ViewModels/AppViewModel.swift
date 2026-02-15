import SwiftUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers

/// Main view model coordinating the app flow, video playback, and pipeline execution
@MainActor
final class AppViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var playbackTime: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var showExportSheet: Bool = false
    @Published var showBatchView: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var isPreviewingAssembled: Bool = false
    @Published var minimumRating: Int = 1
    @Published var currentPreviewIndex: Int = 0

    private var timeObserver: Any?
    private var previewGenerationId: UUID = UUID()
    private var analysisTask: Task<Void, Never>?

    weak var appState: AppState?

    // MARK: - File Import

    func resetForNewFile() {
        stopAssembledPreview()
        cleanupPlayer()
    }

    func importFile(url: URL) {
        guard let appState else { return }

        // Clean up previous state
        resetForNewFile()

        let resources = try? url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(resources?.fileSize ?? 0)

        // Probe media info with AVAsset
        let asset = AVAsset(url: url)
        Task {
            var duration: TimeInterval
            var isVideo: Bool
            var width: Int?
            var height: Int?
            var frameRate: FrameRate?
            var codec: String?

            do {
                let durationCM = try await asset.load(.duration)
                duration = CMTimeGetSeconds(durationCM)

                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                isVideo = !videoTracks.isEmpty

                if let track = videoTracks.first {
                    let size = try await track.load(.naturalSize)
                    width = Int(size.width)
                    height = Int(size.height)
                    let rate = try await track.load(.nominalFrameRate)
                    frameRate = FrameRate.detect(from: Double(rate))
                    let descriptions = try await track.load(.formatDescriptions)
                    if let desc = descriptions.first {
                        let codecType = CMFormatDescriptionGetMediaSubType(desc)
                        codec = fourCharCodeToString(codecType)
                    }
                }
            } catch {
                duration = 0
                isVideo = false
            }

            let fileInfo = MediaFileInfo(
                url: url,
                fileName: url.lastPathComponent,
                fileSize: fileSize,
                duration: duration,
                isVideoFile: isVideo,
                videoWidth: width,
                videoHeight: height,
                frameRate: frameRate,
                codec: codec
            )

            appState.currentFile = fileInfo
            appState.processingState = .idle
            appState.transcription = nil
            appState.analysis = nil
            appState.selectedHighlightId = nil

            // Set up player for both video and audio files
            setupPlayer(url: url)
        }
    }

    // MARK: - Video Playback

    func setupPlayer(url: URL) {
        cleanupPlayer()
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.playbackTime = CMTimeGetSeconds(time)
                let playerIsPlaying = self.player?.rate != 0
                if self.isPlaying != playerIsPlaying {
                    self.isPlaying = playerIsPlaying
                }
            }
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        playbackTime = time
    }

    func playHighlight(_ highlight: Highlight) {
        seek(to: highlight.startTime)
        player?.play()
        isPlaying = true

        // Schedule pause at end time
        let endTime = CMTime(seconds: highlight.endTime, preferredTimescale: 600)
        player?.currentItem?.forwardPlaybackEndTime = endTime
    }

    // MARK: - Analysis Pipeline

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        appState?.processingState = .idle
    }

    func startAnalysis() {
        guard let appState, let file = appState.currentFile else { return }

        analysisTask = Task {
            do {
                guard let service = appState.transcriptionService else {
                    showErrorMessage("Transcription service not configured. Please set API keys in Settings.")
                    return
                }

                // Step 1: Extract audio
                appState.processingState = .extractingAudio(progress: 0)
                // Check for saved session first
                if loadSession() { return }
                try Task.checkCancellation()
                let audioURL = try await service.extractAudio(from: file.url) { progress in
                    Task { @MainActor in
                        appState.processingState = .extractingAudio(progress: progress)
                    }
                }

                // Step 2: Transcribe
                try Task.checkCancellation()
                appState.processingState = .transcribing(progress: 0, estimatedRemaining: nil)
                let apiKey = appState.settings.openAIAPIKey
                let transcript = try await service.transcribe(audioURL: audioURL, apiKey: apiKey) { progress in
                    Task { @MainActor in
                        let remaining = file.duration * (1.0 - progress) * 0.3
                        appState.processingState = .transcribing(progress: progress, estimatedRemaining: remaining)
                    }
                }

                // Step 3: Identify speakers
                try Task.checkCancellation()
                appState.processingState = .identifyingSpeakers
                let diarized = try await service.identifySpeakers(
                    transcript: transcript,
                    apiKey: apiKey,
                    provider: appState.settings.aiProvider,
                    anthropicKey: appState.settings.anthropicAPIKey.isEmpty ? nil : appState.settings.anthropicAPIKey
                )
                appState.transcription = diarized

                // Step 4: Find highlights
                try Task.checkCancellation()
                appState.processingState = .findingHighlights
                let analysis = try await service.findHighlights(
                    transcript: diarized,
                    settings: appState.settings,
                    template: appState.selectedTemplate
                )
                appState.analysis = analysis

                // Done
                appState.processingState = .complete
                saveSession()

            } catch is CancellationError {
                // Cancelled by user — state already reset by cancelAnalysis()
            } catch {
                appState.processingState = .error(error.localizedDescription)
                showErrorMessage(error.localizedDescription)
            }
        }
    }

    // MARK: - Highlight Actions

    func approveHighlight(_ highlight: Highlight) {
        guard let appState, var analysis = appState.analysis else { return }
        if let idx = analysis.highlights.firstIndex(where: { $0.id == highlight.id }) {
            analysis.highlights[idx].isApproved = true
            appState.analysis = analysis
        }
    }

    func rejectHighlight(_ highlight: Highlight) {
        guard let appState, var analysis = appState.analysis else { return }
        if let idx = analysis.highlights.firstIndex(where: { $0.id == highlight.id }) {
            analysis.highlights[idx].isApproved = false
            appState.analysis = analysis
        }
    }

    func updateHighlightRating(_ highlight: Highlight, rating: Int) {
        guard let appState, var analysis = appState.analysis else { return }
        if let idx = analysis.highlights.firstIndex(where: { $0.id == highlight.id }) {
            analysis.highlights[idx].rating = max(1, min(5, rating))
            appState.analysis = analysis
        }
    }

    func adjustHighlightTime(_ highlight: Highlight, startDelta: TimeInterval, endDelta: TimeInterval) {
        guard let appState, var analysis = appState.analysis else { return }
        let mediaDuration = appState.currentFile?.duration ?? .greatestFiniteMagnitude
        if let idx = analysis.highlights.firstIndex(where: { $0.id == highlight.id }) {
            var newStart = analysis.highlights[idx].startTime + startDelta
            var newEnd = analysis.highlights[idx].endTime + endDelta

            // Clamp to valid range
            newStart = max(0, min(newStart, mediaDuration))
            newEnd = max(0, min(newEnd, mediaDuration))

            // Enforce minimum 0.5s duration
            if newEnd - newStart < 0.5 {
                if endDelta != 0 {
                    newEnd = min(newStart + 0.5, mediaDuration)
                } else {
                    newStart = max(newEnd - 0.5, 0)
                }
            }

            analysis.highlights[idx].startTime = newStart
            analysis.highlights[idx].endTime = newEnd
            appState.analysis = analysis
        }
    }

    func reorderHighlights(_ sourceIndices: IndexSet, destination: Int) {
        guard let appState else { return }
        appState.analysis?.highlights.move(fromOffsets: sourceIndices, toOffset: destination)
        // Update sequence numbers
        if var analysis = appState.analysis {
            for i in analysis.highlights.indices {
                analysis.highlights[i].sequenceNumber = i + 1
            }
            appState.analysis = analysis
        }
    }

    // MARK: - Export

    @discardableResult
    func exportHighlights(format: ExportFormat, config: ExportConfig, to url: URL) -> Bool {
        guard let appState,
              let analysis = appState.analysis,
              let file = appState.currentFile,
              let exportService = appState.exportService else {
            showErrorMessage("Export service not available.")
            return false
        }

        do {
            let data: Data
            switch format {
            case .fcpxml:
                data = try exportService.exportFCPXML(analysis: analysis, mediaFile: file, config: config)
            case .premiereXML:
                data = try exportService.exportPremiereXML(analysis: analysis, mediaFile: file, config: config)
            case .edl:
                data = try exportService.exportEDL(analysis: analysis, mediaFile: file, config: config)
            case .csv:
                data = try exportService.exportCSV(analysis: analysis, mediaFile: file)
            case .srt:
                data = try exportService.exportSRT(analysis: analysis)
            case .plainText:
                data = try exportService.exportPlainText(analysis: analysis, transcript: appState.transcription)
            }
            try data.write(to: url)
            return true
        } catch {
            showErrorMessage("Export failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Assembled Preview

    func playAssembledPreview() {
        guard let appState, let analysis = appState.analysis else { return }
        let approved = analysis.approvedHighlights.sorted(by: { $0.startTime < $1.startTime })
        guard !approved.isEmpty else { return }

        let genId = UUID()
        previewGenerationId = genId
        isPreviewingAssembled = true
        currentPreviewIndex = 0
        playClipAtIndex(0, in: approved, generationId: genId)
    }

    func stopAssembledPreview() {
        previewGenerationId = UUID() // Invalidate any pending scheduled clips
        isPreviewingAssembled = false
        player?.pause()
        isPlaying = false
        player?.currentItem?.forwardPlaybackEndTime = .invalid
    }

    private func playClipAtIndex(_ index: Int, in clips: [Highlight], generationId: UUID) {
        guard index < clips.count, generationId == previewGenerationId else {
            stopAssembledPreview()
            return
        }
        currentPreviewIndex = index
        let clip = clips[index]
        seek(to: clip.startTime)
        player?.play()
        isPlaying = true

        // Set end time for this clip
        let endTime = CMTime(seconds: clip.endTime, preferredTimescale: 600)
        player?.currentItem?.forwardPlaybackEndTime = endTime

        // Schedule next clip with generation check to prevent stale callbacks
        let clipDuration = clip.endTime - clip.startTime
        let capturedGenId = generationId
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(round(clipDuration * 1_000_000_000)))
            // Only advance if this preview session is still active
            if isPreviewingAssembled && previewGenerationId == capturedGenId {
                playClipAtIndex(index + 1, in: clips, generationId: capturedGenId)
            }
        }
    }

    // MARK: - Smart Auto-Fit

    func autoFitToTargetDuration() {
        guard let appState, var analysis = appState.analysis else { return }
        let targetSeconds = TimeInterval(appState.settings.targetDurationSeconds)
        guard targetSeconds > 0 else { return }

        // Sort by rating descending, then by duration ascending (prefer short punchy clips)
        let sorted = analysis.highlights.sorted { a, b in
            if a.rating != b.rating { return a.rating > b.rating }
            return a.duration < b.duration
        }

        // Greedily select best clips until we hit target
        var totalDuration: TimeInterval = 0
        var selectedIds: Set<UUID> = []

        for highlight in sorted {
            if totalDuration + highlight.duration <= targetSeconds * 1.1 { // 10% tolerance
                selectedIds.insert(highlight.id)
                totalDuration += highlight.duration
            }
        }

        // Update all highlights
        for i in analysis.highlights.indices {
            analysis.highlights[i].isApproved = selectedIds.contains(analysis.highlights[i].id)
        }
        appState.analysis = analysis
    }

    // MARK: - Session Save/Restore

    func saveSession() {
        guard let appState, let file = appState.currentFile,
              let transcription = appState.transcription,
              let analysis = appState.analysis else { return }

        let session = SessionData(
            mediaURL: file.url,
            mediaFileName: file.fileName,
            transcription: transcription,
            analysis: analysis,
            savedAt: Date()
        )
        SessionData.save(session, for: file.fileName)
    }

    func loadSession() -> Bool {
        guard let appState, let file = appState.currentFile else { return false }
        guard let session = SessionData.load(for: file.fileName) else { return false }

        // Verify the media file still exists at its original path
        guard FileManager.default.fileExists(atPath: file.url.path) else { return false }

        appState.transcription = session.transcription
        appState.analysis = session.analysis
        appState.processingState = .complete
        return true
    }

    // MARK: - Re-Analyze

    func reAnalyze() {
        guard let appState, let transcript = appState.transcription else { return }

        Task {
            do {
                guard let service = appState.transcriptionService else { return }
                appState.processingState = .findingHighlights
                let analysis = try await service.findHighlights(
                    transcript: transcript,
                    settings: appState.settings,
                    template: appState.selectedTemplate
                )
                appState.analysis = analysis
                appState.processingState = .complete
                saveSession()
            } catch {
                appState.processingState = .error(error.localizedDescription)
                showErrorMessage(error.localizedDescription)
            }
        }
    }

    // MARK: - Sort Highlights

    func sortHighlights(by order: HighlightSortOrder) {
        guard let appState, var analysis = appState.analysis else { return }
        switch order {
        case .chronological:
            analysis.highlights.sort { $0.startTime < $1.startTime }
        case .aiSuggested:
            let orderMap = Dictionary(uniqueKeysWithValues: analysis.suggestedTeaserOrder.enumerated().map { ($1, $0) })
            analysis.highlights.sort { a, b in
                (orderMap[a.sequenceNumber] ?? 999) < (orderMap[b.sequenceNumber] ?? 999)
            }
        case .byRating:
            analysis.highlights.sort { $0.rating > $1.rating }
        case .bySpeaker:
            analysis.highlights.sort { $0.speakerId.uuidString < $1.speakerId.uuidString }
        }
        // Re-number
        for i in analysis.highlights.indices {
            analysis.highlights[i].sequenceNumber = i + 1
        }
        appState.analysis = analysis
    }

    // MARK: - Computed Properties

    var approvedClipsCount: Int {
        appState?.analysis?.approvedHighlights.count ?? 0
    }

    var approvedDuration: TimeInterval {
        appState?.analysis?.approvedDuration ?? 0
    }

    var hasAPIKey: Bool {
        guard let appState else { return false }
        // OpenAI key is always required for Whisper transcription
        guard !appState.settings.openAIAPIKey.isEmpty else { return false }
        // If using Anthropic for analysis, also need an Anthropic key
        if appState.settings.aiProvider == .anthropic {
            return !appState.settings.anthropicAPIKey.isEmpty
        }
        return true
    }

    // MARK: - Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
    }

    private func fourCharCodeToString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "unknown"
    }

    deinit {
        // Note: deinit runs on arbitrary thread, cleanup done via cleanupPlayer calls
    }
}

// MARK: - Formatting Helpers

extension TimeInterval {
    /// Format as MM:SS
    var mmss: String {
        let mins = Int(self) / 60
        let secs = Int(self) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Format as HH:MM:SS:FF (timecode)
    func timecode(fps: Double = 30) -> String {
        let totalFrames = Int(self * fps)
        let frames = totalFrames % Int(fps)
        let totalSeconds = Int(self)
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}

extension Int64 {
    /// Format bytes as human-readable size
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}
