import AVFoundation
import Foundation

/// Extracts audio from video files using AVFoundation
struct AudioExtractor {

    enum ExtractionError: LocalizedError {
        case noAudioTrack
        case exportFailed(String)
        case exportCancelled

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: return "No audio track found in the media file."
            case .exportFailed(let reason): return "Audio extraction failed: \(reason)"
            case .exportCancelled: return "Audio extraction was cancelled."
            }
        }
    }

    private static let audioOnlyExtensions: Set<String> = ["wav", "mp3", "m4a"]

    /// Extract audio from a video file as M4A. If the input is already audio-only, returns the URL directly.
    static func extractAudio(
        from url: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        if audioOnlyExtensions.contains(ext) {
            progressHandler(1.0)
            return url
        }

        let asset = AVAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw ExtractionError.noAudioTrack
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExtractionError.exportFailed("Could not create export session.")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        let progressTask = Task {
            while !Task.isCancelled {
                let progress = Double(exportSession.progress)
                await MainActor.run { progressHandler(progress) }
                if exportSession.status == .completed || exportSession.status == .failed || exportSession.status == .cancelled {
                    break
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        await exportSession.export()
        progressTask.cancel()

        switch exportSession.status {
        case .completed:
            progressHandler(1.0)
            return outputURL
        case .failed:
            let message = exportSession.error?.localizedDescription ?? "Unknown error"
            throw ExtractionError.exportFailed(message)
        case .cancelled:
            throw ExtractionError.exportCancelled
        default:
            throw ExtractionError.exportFailed("Unexpected export status: \(exportSession.status.rawValue)")
        }
    }
}
