import Foundation
import WhisperKit

/// Manages on-device transcription via WhisperKit (CoreML + Neural Engine)
@MainActor
final class LocalWhisperService: ObservableObject {
    static let shared = LocalWhisperService()

    @Published var modelState: ModelState = .notDownloaded
    @Published var downloadProgress: Double = 0
    @Published var downloadSpeed: String = ""
    @Published var downloadETA: String = ""
    @Published var downloadedSize: String = ""
    @Published var totalSize: String = ""
    @Published var downloadingModelName: String = ""

    enum ModelState: Equatable {
        case notDownloaded
        case downloading
        case loading
        case ready
        case error(String)
    }

    private var whisperKit: WhisperKit?
    private var loadedModel: String?
    private var downloadStartTime: Date?
    private var lastProgressUpdate: Date?
    private var lastBytes: Int64 = 0

    // MARK: - Model Management

    /// Download and load the model with progress tracking
    func prepareModel(variant: LocalWhisperModel) async throws {
        if loadedModel == variant.rawValue, whisperKit != nil {
            return // Already loaded
        }

        // Reset state
        whisperKit = nil
        loadedModel = nil
        modelState = .downloading
        downloadProgress = 0
        downloadSpeed = ""
        downloadETA = ""
        downloadedSize = ""
        totalSize = ""
        downloadingModelName = variant.displayName
        downloadStartTime = Date()
        lastProgressUpdate = Date()
        lastBytes = 0

        do {
            // Step 1: Download model with progress callback
            let modelFolder = try await WhisperKit.download(
                variant: variant.rawValue,
                progressCallback: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.updateDownloadProgress(progress)
                    }
                }
            )

            // Step 2: Load the downloaded model
            modelState = .loading
            downloadProgress = 1.0

            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )

            whisperKit = try await WhisperKit(config)
            loadedModel = variant.rawValue
            modelState = .ready
        } catch {
            modelState = .error(error.localizedDescription)
            throw error
        }
    }

    private func updateDownloadProgress(_ progress: Progress) {
        let fraction = progress.fractionCompleted
        downloadProgress = fraction

        let completed = progress.completedUnitCount
        let total = progress.totalUnitCount

        // Format sizes
        downloadedSize = formatBytes(completed)
        if total > 0 {
            totalSize = formatBytes(total)
        }

        // Calculate speed and ETA
        let now = Date()
        if let startTime = downloadStartTime {
            let elapsed = now.timeIntervalSince(startTime)
            if elapsed > 0.5 && completed > 0 {
                let bytesPerSecond = Double(completed) / elapsed
                downloadSpeed = "\(formatBytes(Int64(bytesPerSecond)))/s"

                if total > 0 && bytesPerSecond > 0 {
                    let remaining = Double(total - completed) / bytesPerSecond
                    downloadETA = formatDuration(remaining)
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return "\(mins)m \(secs)s"
        } else {
            let hours = Int(seconds) / 3600
            let mins = (Int(seconds) % 3600) / 60
            return "\(hours)h \(mins)m"
        }
    }

    /// Check if a model is already downloaded/cached
    func isModelReady(variant: LocalWhisperModel) -> Bool {
        loadedModel == variant.rawValue && whisperKit != nil
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> TranscriptionResult {
        guard let wk = whisperKit else {
            throw LocalWhisperError.modelNotLoaded
        }

        progressHandler(0.05)

        let options = DecodingOptions(
            task: .transcribe,
            wordTimestamps: true
        )

        let wkResults = try await wk.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )

        progressHandler(1.0)

        // Convert WhisperKit results to our app's model types
        var allSegments: [TranscriptionSegment] = []
        var fullText = ""
        var detectedLanguage: String?

        for wkResult in wkResults {
            detectedLanguage = detectedLanguage ?? wkResult.language

            for wkSegment in wkResult.segments {
                let words: [TranscriptionWord] = (wkSegment.words ?? []).map { wt in
                    TranscriptionWord(
                        word: wt.word,
                        start: TimeInterval(wt.start),
                        end: TimeInterval(wt.end)
                    )
                }

                allSegments.append(TranscriptionSegment(
                    text: wkSegment.text.trimmingCharacters(in: .whitespaces),
                    start: TimeInterval(wkSegment.start),
                    end: TimeInterval(wkSegment.end),
                    words: words
                ))
            }

            if !fullText.isEmpty { fullText += " " }
            fullText += wkResult.text
        }

        let duration = allSegments.last?.end ?? 0

        return TranscriptionResult(
            segments: allSegments,
            fullText: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration,
            language: detectedLanguage
        )
    }

    // MARK: - Errors

    enum LocalWhisperError: LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Local Whisper model is not loaded. Please download a model in Settings first."
            }
        }
    }
}
