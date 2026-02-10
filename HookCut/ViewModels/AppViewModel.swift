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

    private var timeObserver: Any?

    weak var appState: AppState?

    // MARK: - File Import

    func importFile(url: URL) {
        guard let appState else { return }

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

            if isVideo {
                setupPlayer(url: url)
            }
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
                self?.playbackTime = CMTimeGetSeconds(time)
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

    func startAnalysis() {
        guard let appState, let file = appState.currentFile else { return }

        Task {
            do {
                guard let service = appState.transcriptionService else {
                    showErrorMessage("Transcription service not configured. Please set API keys in Settings.")
                    return
                }

                // Step 1: Extract audio
                appState.processingState = .extractingAudio(progress: 0)
                let audioURL = try await service.extractAudio(from: file.url) { progress in
                    Task { @MainActor in
                        appState.processingState = .extractingAudio(progress: progress)
                    }
                }

                // Step 2: Transcribe
                appState.processingState = .transcribing(progress: 0, estimatedRemaining: nil)
                let apiKey = appState.settings.openAIAPIKey
                let transcript = try await service.transcribe(audioURL: audioURL, apiKey: apiKey) { progress in
                    Task { @MainActor in
                        let remaining = file.duration * (1.0 - progress) * 0.3
                        appState.processingState = .transcribing(progress: progress, estimatedRemaining: remaining)
                    }
                }

                // Step 3: Identify speakers
                appState.processingState = .identifyingSpeakers
                let diarized = try await service.identifySpeakers(
                    transcript: transcript,
                    apiKey: apiKey,
                    provider: appState.settings.aiProvider,
                    anthropicKey: appState.settings.anthropicAPIKey.isEmpty ? nil : appState.settings.anthropicAPIKey
                )
                appState.transcription = diarized

                // Step 4: Find highlights
                appState.processingState = .findingHighlights
                let analysis = try await service.findHighlights(
                    transcript: diarized,
                    settings: appState.settings
                )
                appState.analysis = analysis

                // Done
                let speakerCount = analysis.speakers.count
                let highlightCount = analysis.highlights.count
                appState.processingState = .complete
                _ = speakerCount
                _ = highlightCount

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
        if let idx = analysis.highlights.firstIndex(where: { $0.id == highlight.id }) {
            analysis.highlights[idx].startTime += startDelta
            analysis.highlights[idx].endTime += endDelta
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

    func exportHighlights(format: ExportFormat, config: ExportConfig, to url: URL) {
        guard let appState,
              let analysis = appState.analysis,
              let file = appState.currentFile,
              let exportService = appState.exportService else {
            showErrorMessage("Export service not available.")
            return
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
        } catch {
            showErrorMessage("Export failed: \(error.localizedDescription)")
        }
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
        switch appState.settings.aiProvider {
        case .openAI:
            return !appState.settings.openAIAPIKey.isEmpty
        case .anthropic:
            return !appState.settings.anthropicAPIKey.isEmpty
        }
    }

    var costEstimate: CostEstimate? {
        guard let duration = appState?.currentFile?.duration, duration > 0 else { return nil }
        return CostEstimate.estimate(durationSeconds: duration)
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
