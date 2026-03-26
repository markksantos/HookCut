import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

/// Batch processing view for handling multiple files
struct BatchView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false
    @State private var isProcessing = false
    @State private var currentProcessingIndex: Int?

    private let acceptedTypes: [UTType] = [
        .mpeg4Movie, .quickTimeMovie, .movie,
        .mpeg4Audio, .mp3, .wav, .audio
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Batch Processing")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            if appState.batchItems.isEmpty {
                emptyState
            } else {
                batchList
            }

            Divider()

            // Bottom controls
            HStack {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Add Files", systemImage: "plus")
                }

                Spacer()

                if !appState.batchItems.isEmpty {
                    Button("Clear All", role: .destructive) {
                        appState.batchItems.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .disabled(isProcessing)

                    Button {
                        Task { await processBatch() }
                    } label: {
                        if isProcessing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                if let idx = currentProcessingIndex {
                                    Text("\(idx + 1)/\(appState.batchItems.count)")
                                        .font(.caption)
                                }
                            }
                        } else {
                            Label("Process All", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing || !hasAPIKey || allComplete)
                }
            }
            .padding()

            if !hasAPIKey {
                Text("Set API key in Settings to enable processing")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 600, height: 500)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: acceptedTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    await addFiles(urls)
                }
            }
        }
    }

    private var hasAPIKey: Bool {
        !appState.settings.openAIAPIKey.isEmpty
    }

    private var allComplete: Bool {
        appState.batchItems.allSatisfy { item in
            if case .complete = item.state { return true }
            return false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No files added")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Add video or audio files to process them in batch")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var batchList: some View {
        List {
            ForEach(appState.batchItems) { item in
                HStack(spacing: 12) {
                    statusIcon(for: item.state)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileInfo.fileName)
                            .font(.callout)
                        HStack(spacing: 8) {
                            statusLabel(for: item.state)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if item.fileInfo.duration > 0 {
                                Text(item.fileInfo.duration.mmss)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            if item.fileInfo.fileSize > 0 {
                                Text(item.fileInfo.fileSize.formattedFileSize)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer()

                    if let analysis = item.analysis {
                        Text("\(analysis.highlights.count) highlights")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    progressIndicator(for: item.state)
                }
                .padding(.vertical, 4)
            }
            .onDelete { indices in
                guard !isProcessing else { return }
                appState.batchItems.remove(atOffsets: indices)
            }
        }
    }

    private func statusIcon(for state: ProcessingState) -> some View {
        Group {
            switch state {
            case .idle:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            case .extractingAudio, .transcribing, .identifyingSpeakers, .findingHighlights:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func statusLabel(for state: ProcessingState) -> some View {
        Group {
            switch state {
            case .idle:
                Text("Waiting")
            case .extractingAudio:
                Text("Extracting audio...")
            case .transcribing:
                Text("Transcribing...")
            case .identifyingSpeakers:
                Text("Identifying speakers...")
            case .findingHighlights:
                Text("Finding highlights...")
            case .complete:
                Text("Complete")
            case .error(let msg):
                Text("Error: \(msg)")
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func progressIndicator(for state: ProcessingState) -> some View {
        switch state {
        case .extractingAudio(let progress):
            ProgressView(value: progress)
                .frame(width: 100)
        case .transcribing(let progress, _):
            ProgressView(value: progress)
                .frame(width: 100)
        case .identifyingSpeakers, .findingHighlights:
            ProgressView()
                .controlSize(.small)
        default:
            EmptyView()
        }
    }

    // MARK: - File Handling

    @MainActor
    private func addFiles(_ urls: [URL]) async {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            // Probe actual file info
            let resources = try? url.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(resources?.fileSize ?? 0)

            var duration: TimeInterval = 0
            var isVideo = false
            let asset = AVAsset(url: url)
            if let durationCM = try? await asset.load(.duration) {
                duration = CMTimeGetSeconds(durationCM)
            }
            if let videoTracks = try? await asset.loadTracks(withMediaType: .video) {
                isVideo = !videoTracks.isEmpty
            }

            let info = MediaFileInfo(
                url: url,
                fileName: url.lastPathComponent,
                fileSize: fileSize,
                duration: duration,
                isVideoFile: isVideo
            )
            appState.batchItems.append(BatchItem(fileInfo: info))
        }
    }

    // MARK: - Batch Processing

    @MainActor
    private func processBatch() async {
        guard let service = appState.transcriptionService else { return }
        isProcessing = true

        for i in appState.batchItems.indices {
            guard case .idle = appState.batchItems[i].state else { continue }
            currentProcessingIndex = i

            do {
                let item = appState.batchItems[i]

                // Extract audio
                appState.batchItems[i].state = .extractingAudio(progress: 0)
                let audioURL = try await service.extractAudio(from: item.fileInfo.url) { progress in
                    Task { @MainActor in
                        self.appState.batchItems[i].state = .extractingAudio(progress: progress)
                    }
                }

                // Transcribe
                appState.batchItems[i].state = .transcribing(progress: 0, estimatedRemaining: nil)
                let transcript = try await service.transcribe(
                    audioURL: audioURL,
                    apiKey: appState.settings.openAIAPIKey
                ) { progress in
                    Task { @MainActor in
                        self.appState.batchItems[i].state = .transcribing(progress: progress, estimatedRemaining: nil)
                    }
                }

                // Identify speakers
                appState.batchItems[i].state = .identifyingSpeakers
                let diarized = try await service.identifySpeakers(
                    transcript: transcript,
                    apiKey: appState.settings.openAIAPIKey,
                    provider: appState.settings.aiProvider,
                    anthropicKey: appState.settings.anthropicAPIKey.isEmpty ? nil : appState.settings.anthropicAPIKey,
                    ollamaModel: appState.settings.ollamaModel
                )
                appState.batchItems[i].transcription = diarized

                // Find highlights
                appState.batchItems[i].state = .findingHighlights
                let analysis = try await service.findHighlights(
                    transcript: diarized,
                    settings: appState.settings,
                    template: appState.selectedTemplate
                )
                appState.batchItems[i].analysis = analysis
                appState.batchItems[i].state = .complete

            } catch {
                appState.batchItems[i].state = .error(error.localizedDescription)
            }
        }

        currentProcessingIndex = nil
        isProcessing = false
    }
}
