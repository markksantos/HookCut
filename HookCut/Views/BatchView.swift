import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import AppKit

/// Batch processing view for handling multiple files
struct BatchView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false
    @State private var isProcessing = false
    @State private var currentProcessingIndex: Int?
    @State private var batchTask: Task<Void, Never>?
    @State private var isExporting = false
    @State private var exportMessage: String?

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

                    if hasCompletedItems && !isProcessing {
                        Button {
                            exportAll()
                        } label: {
                            if isExporting {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Export All", systemImage: "square.and.arrow.up")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isExporting)
                        .help("Export every completed item to a folder in your default format")
                    }

                    if isProcessing {
                        Button(role: .destructive) {
                            cancelBatch()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        startBatch()
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

            if let exportMessage {
                Text(exportMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.bottom, 8)
            }

            if !hasAPIKey {
                Text(needsAPIKeyMessage)
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

    /// Whether the current settings can run the pipeline (mirrors AppViewModel.hasAPIKey).
    private var hasAPIKey: Bool {
        let settings = appState.settings
        if settings.transcriptionEngine == .cloud && settings.openAIAPIKey.isEmpty {
            return false
        }
        switch settings.aiProvider {
        case .ollama: return true
        case .anthropic: return !settings.anthropicAPIKey.isEmpty
        case .openAI: return !settings.openAIAPIKey.isEmpty
        }
    }

    private var needsAPIKeyMessage: String {
        if appState.settings.transcriptionEngine == .cloud && appState.settings.openAIAPIKey.isEmpty {
            return "OpenAI API key required for cloud transcription (Settings ⌘,)"
        }
        if appState.settings.aiProvider == .anthropic && appState.settings.anthropicAPIKey.isEmpty {
            return "Anthropic API key required for analysis (Settings ⌘,)"
        }
        return "Set an API key in Settings to enable processing"
    }

    private var allComplete: Bool {
        appState.batchItems.allSatisfy { item in
            if case .complete = item.state { return true }
            return false
        }
    }

    private var hasCompletedItems: Bool {
        appState.batchItems.contains { item in
            if case .complete = item.state { return item.analysis != nil }
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

    private func startBatch() {
        exportMessage = nil
        batchTask = Task { await processBatch() }
    }

    private func cancelBatch() {
        batchTask?.cancel()
    }

    @MainActor
    private func processBatch() async {
        guard let service = appState.transcriptionService else { return }
        isProcessing = true
        defer {
            currentProcessingIndex = nil
            isProcessing = false
            batchTask = nil
        }

        let useLocal = appState.settings.transcriptionEngine == .local
        if useLocal {
            // Ensure the on-device model is downloaded/loaded once up front.
            do {
                try await LocalWhisperService.shared.prepareModel(variant: appState.settings.localModelVariant)
            } catch {
                // Surface the failure on the first idle item and stop.
                if let i = appState.batchItems.firstIndex(where: { if case .idle = $0.state { return true }; return false }) {
                    appState.batchItems[i].state = .error("Model load failed: \(error.localizedDescription)")
                }
                return
            }
        }

        for i in appState.batchItems.indices {
            if Task.isCancelled { return }
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
                try Task.checkCancellation()

                // Transcribe (cloud or local, matching the user's setting)
                appState.batchItems[i].state = .transcribing(progress: 0, estimatedRemaining: nil)
                let transcript: TranscriptionResult
                if useLocal {
                    transcript = try await service.transcribeLocally(audioURL: audioURL) { progress in
                        Task { @MainActor in
                            self.appState.batchItems[i].state = .transcribing(progress: progress, estimatedRemaining: nil)
                        }
                    }
                } else {
                    transcript = try await service.transcribe(
                        audioURL: audioURL,
                        apiKey: appState.settings.openAIAPIKey
                    ) { progress in
                        Task { @MainActor in
                            self.appState.batchItems[i].state = .transcribing(progress: progress, estimatedRemaining: nil)
                        }
                    }
                }
                try Task.checkCancellation()

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
                try Task.checkCancellation()

                // Find highlights
                appState.batchItems[i].state = .findingHighlights
                let analysis = try await service.findHighlights(
                    transcript: diarized,
                    settings: appState.settings,
                    template: appState.selectedTemplate
                )
                appState.batchItems[i].analysis = analysis
                appState.batchItems[i].state = .complete

            } catch is CancellationError {
                // Reset the in-flight item so it can be re-run later.
                appState.batchItems[i].state = .idle
                return
            } catch {
                appState.batchItems[i].state = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Batch Export

    private func exportAll() {
        guard let exportService = appState.exportService else { return }
        let format = appState.settings.defaultExportFormat
        let config = ExportConfig(
            format: format,
            gapDuration: appState.settings.defaultGapDuration,
            includeMarkers: true,
            projectName: "Batch Highlights"
        )

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.title = "Choose a folder for batch exports"

        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor in
                isExporting = true
                defer { isExporting = false }

                var written = 0
                for item in appState.batchItems {
                    guard case .complete = item.state, let analysis = item.analysis else { continue }
                    guard !analysis.approvedHighlights.isEmpty else { continue }

                    let baseName = (item.fileInfo.fileName as NSString).deletingPathExtension
                    let outURL = folder
                        .appendingPathComponent("\(baseName)-highlights")
                        .appendingPathExtension(format.fileExtension)
                    do {
                        let data: Data
                        switch format {
                        case .fcpxml:
                            data = try exportService.exportFCPXML(analysis: analysis, mediaFile: item.fileInfo, config: config)
                        case .premiereXML:
                            data = try exportService.exportPremiereXML(analysis: analysis, mediaFile: item.fileInfo, config: config)
                        case .edl:
                            data = try exportService.exportEDL(analysis: analysis, mediaFile: item.fileInfo, config: config)
                        case .csv:
                            data = try exportService.exportCSV(analysis: analysis, mediaFile: item.fileInfo)
                        case .srt:
                            data = try exportService.exportSRT(analysis: analysis)
                        case .plainText:
                            data = try exportService.exportPlainText(analysis: analysis, transcript: item.transcription)
                        }
                        try data.write(to: outURL)
                        written += 1
                    } catch {
                        // Skip items that fail (e.g. no approved highlights) and keep going.
                        continue
                    }
                }
                exportMessage = "Exported \(written) file\(written == 1 ? "" : "s") as \(format.rawValue)"
            }
        }
    }
}
