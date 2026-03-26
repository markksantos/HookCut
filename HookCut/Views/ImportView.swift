import SwiftUI
import UniformTypeIdentifiers

/// Left sidebar view for file import, info display, and processing progress
struct ImportView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: AppViewModel
    @State private var isTargeted = false
    @State private var showFileImporter = false

    private let acceptedTypes: [UTType] = [
        .mpeg4Movie, .quickTimeMovie, .movie,
        .mpeg4Audio, .mp3, .wav, .audio
    ]

    var body: some View {
        VStack(spacing: 0) {
            if appState.currentFile == nil {
                dropZone
            } else {
                fileInfoSection
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: acceptedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessedURL = appState.beginAccessingFile(url)
                viewModel.importFile(url: accessedURL)
            case .failure(let error):
                viewModel.errorMessage = "File import failed: \(error.localizedDescription)"
                viewModel.showError = true
            }
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Drop video or audio file here")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("MP4, MOV, M4V, WAV, MP3, M4A")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button("Browse Files") {
                    showFileImporter = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary.opacity(0.5))
            }
            .background {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.05))
                }
            }
            .onDrop(of: acceptedTypes, isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }

            Spacer()
        }
    }

    // MARK: - File Info

    private var fileInfoSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fileInfoCard
                costEstimateCard
                analysisButton
                processingProgress
                newFileButton
            }
        }
    }

    private var fileInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("File Info", systemImage: "doc.fill")
                .font(.headline)

            if let file = appState.currentFile {
                Group {
                    infoRow("Name", file.fileName)
                    infoRow("Duration", file.duration.mmss)
                    infoRow("Size", file.fileSize.formattedFileSize)
                    if let codec = file.codec {
                        infoRow("Codec", codec)
                    }
                    if let w = file.videoWidth, let h = file.videoHeight {
                        infoRow("Resolution", "\(w) x \(h)")
                    }
                    if let fr = file.frameRate {
                        infoRow("Frame Rate", String(format: "%.2f fps", fr.fps))
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var costEstimateCard: some View {
        Group {
            if let duration = appState.currentFile?.duration, duration > 0 {
                let estimate = CostEstimatorService.estimate(
                    durationSeconds: duration,
                    provider: appState.settings.aiProvider
                )
                VStack(alignment: .leading, spacing: 6) {
                    Label("Cost Estimate", systemImage: "dollarsign.circle")
                        .font(.headline)
                    Text("Estimated cost: \(estimate.formattedTotal)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(estimate.breakdown)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%.1f min audio | ~%d tokens", estimate.audioDurationMinutes, estimate.estimatedTotalInputTokens))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var analysisButton: some View {
        Group {
            if case .idle = appState.processingState {
                VStack(spacing: 8) {
                    // Target duration picker
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Target Duration", systemImage: "timer")
                            .font(.subheadline.weight(.medium))

                        HStack(spacing: 8) {
                            Toggle("Auto", isOn: Binding(
                                get: { appState.settings.targetDurationSeconds == 0 },
                                set: { appState.settings.targetDurationSeconds = $0 ? 0 : 60 }
                            ))
                            .toggleStyle(.checkbox)

                            Spacer()

                            if appState.settings.targetDurationSeconds > 0 {
                                TextField("", value: Binding(
                                    get: { appState.settings.targetDurationSeconds / 60 },
                                    set: { mins in
                                        let clampedMins = max(0, min(180, mins))
                                        let secs = appState.settings.targetDurationSeconds % 60
                                        appState.settings.targetDurationSeconds = max(5, clampedMins * 60 + secs)
                                    }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 44)
                                .multilineTextAlignment(.trailing)

                                Text("min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                TextField("", value: Binding(
                                    get: { appState.settings.targetDurationSeconds % 60 },
                                    set: { secs in
                                        let clampedSecs = max(0, min(59, secs))
                                        let mins = appState.settings.targetDurationSeconds / 60
                                        appState.settings.targetDurationSeconds = max(5, mins * 60 + clampedSecs)
                                    }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 44)
                                .multilineTextAlignment(.trailing)

                                Text("sec")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: appState.settings.targetDurationSeconds) {
                            appState.saveSettings()
                        }
                    }
                    .padding()
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button {
                        viewModel.startAnalysis()
                    } label: {
                        Label("Analyze", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!viewModel.hasAPIKey)

                    if !viewModel.hasAPIKey {
                        VStack(alignment: .leading, spacing: 2) {
                            if appState.settings.transcriptionEngine == .cloud && appState.settings.openAIAPIKey.isEmpty {
                                Text("OpenAI API key required (for cloud transcription)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            if appState.settings.aiProvider == .openAI && appState.settings.openAIAPIKey.isEmpty {
                                Text("OpenAI API key required (for highlight analysis)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            if appState.settings.aiProvider == .anthropic && appState.settings.anthropicAPIKey.isEmpty {
                                Text("Anthropic API key required (selected as AI provider)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Text("Set in Settings (Cmd+,)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if case .complete = appState.processingState {
                // Re-analyze button (keeps transcript, re-runs highlight detection)
                Button {
                    viewModel.reAnalyze()
                } label: {
                    Label("Re-Analyze Highlights", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Keep transcript, re-run highlight detection with current settings")
            }
        }
    }

    private var processingProgress: some View {
        Group {
            switch appState.processingState {
            case .idle:
                EmptyView()
            case .extractingAudio(let progress):
                progressCard("Extracting audio...", progress: progress)
                cancelButton
            case .transcribing(let progress, let remaining):
                VStack(alignment: .leading, spacing: 6) {
                    progressCard("Transcribing...", progress: progress)
                    if let remaining, remaining > 0 {
                        Text("~\(Int(remaining))s remaining")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal)
                    }
                }
                cancelButton
            case .identifyingSpeakers:
                indeterminateCard("Identifying speakers...")
                cancelButton
            case .findingHighlights:
                indeterminateCard("Finding highlights...")
                cancelButton
            case .complete:
                completionCard
            case .error(let message):
                errorCard(message)
            }
        }
    }

    private var completionCard: some View {
        Group {
            if let analysis = appState.analysis, analysis.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("No Highlights Found", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Try adjusting your settings, enabling more highlight types, or modifying the custom prompt.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Analysis Complete", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    if let analysis = appState.analysis {
                        Text("Found \(analysis.highlights.count) highlights from \(analysis.speakers.count) speakers")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var newFileButton: some View {
        Button {
            viewModel.resetForNewFile()
            appState.stopAccessingCurrentFile()
            appState.currentFile = nil
            appState.processingState = .idle
            appState.transcription = nil
            appState.analysis = nil
            appState.selectedHighlightId = nil
        } label: {
            Label("New File", systemImage: "plus.circle")
        }
        .buttonStyle(.borderless)
    }

    private var cancelButton: some View {
        Button(role: .destructive) {
            viewModel.cancelAnalysis()
        } label: {
            Label("Cancel", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    // MARK: - Helper Views

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
    }

    private func progressCard(_ title: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            ProgressView(value: progress)
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func indeterminateCard(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.subheadline.weight(.medium))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        for type in acceptedTypes {
            if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { [weak appState] item, _ in
                    if let url = item as? URL {
                        Task { @MainActor in
                            let accessedURL = appState?.beginAccessingFile(url) ?? url
                            viewModel.importFile(url: accessedURL)
                        }
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Task { @MainActor in
                            let accessedURL = appState?.beginAccessingFile(url) ?? url
                            viewModel.importFile(url: accessedURL)
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}
