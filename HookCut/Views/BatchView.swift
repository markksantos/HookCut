import SwiftUI
import UniformTypeIdentifiers

/// Batch processing view for handling multiple files
struct BatchView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false
    @State private var isProcessing = false

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

                    Button {
                        processBatch()
                    } label: {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Process All", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: acceptedTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let info = MediaFileInfo(
                        url: url,
                        fileName: url.lastPathComponent,
                        fileSize: 0,
                        duration: 0,
                        isVideoFile: url.pathExtension.lowercased() != "mp3" && url.pathExtension.lowercased() != "wav"
                    )
                    appState.batchItems.append(BatchItem(fileInfo: info))
                }
            }
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
            Text("Add files to process them in batch")
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
                        statusLabel(for: item.state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    progressIndicator(for: item.state)
                }
                .padding(.vertical, 4)
            }
            .onDelete { indices in
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

    private func processBatch() {
        isProcessing = true
        // Batch processing would be implemented via the transcription service
        // For now, mark as placeholder until services are connected
        isProcessing = false
    }
}
