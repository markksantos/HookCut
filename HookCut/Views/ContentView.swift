import SwiftUI
import AVKit

/// Main content view - three-panel layout with bottom highlights panel
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        Group {
            if appState.currentFile == nil {
                ImportView(viewModel: viewModel)
            } else {
                mainLayout
            }
        }
        .onAppear {
            viewModel.appState = appState
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.showError = false }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $viewModel.showExportSheet) {
            ExportSheet(viewModel: viewModel)
                .environmentObject(appState)
        }
        .sheet(isPresented: $viewModel.showBatchView) {
            BatchView()
                .environmentObject(appState)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.showBatchView = true
                } label: {
                    Label("Batch", systemImage: "square.stack.3d.up")
                }
                .help("Batch process multiple files")

                if appState.currentFile != nil {
                    Button {
                        viewModel.showExportSheet = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(appState.analysis == nil)
                    .help("Export highlights")
                }
            }
        }
    }

    private var mainLayout: some View {
        VSplitView {
            HSplitView {
                // Left sidebar: Import & file info
                ImportView(viewModel: viewModel)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)

                // Center: Video player
                VideoPlayerView(viewModel: viewModel)
                    .frame(minWidth: 400)

                // Right sidebar: Transcript
                if appState.transcription != nil {
                    TranscriptView(viewModel: viewModel)
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                }
            }
            .frame(minHeight: 350)

            // Bottom: Highlights panel
            if appState.analysis != nil {
                HighlightsPanel(viewModel: viewModel)
                    .frame(minHeight: 200, idealHeight: 250, maxHeight: 400)
            }
        }
    }
}
