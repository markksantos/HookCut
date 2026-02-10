import SwiftUI
import AVKit
import AVFoundation

/// Video player view wrapping AVPlayerView in NSViewRepresentable
struct VideoPlayerView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let player = viewModel.player, appState.currentFile?.isVideoFile == true {
                AVPlayerViewRepresentable(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                timecodeBar
            } else if appState.currentFile != nil {
                // Audio-only file
                audioPlaceholder
                timecodeBar
            } else {
                emptyState
            }
        }
        .background(.black.opacity(0.05))
    }

    private var timecodeBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.space, modifiers: [])

            let fps = appState.currentFile?.frameRate?.fps ?? 30
            Text(viewModel.playbackTime.timecode(fps: fps))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            if let duration = appState.currentFile?.duration, duration > 0 {
                Slider(
                    value: Binding(
                        get: { viewModel.playbackTime },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...duration
                )

                Text(duration.mmss)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var audioPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Audio File")
                .font(.title3)
                .foregroundStyle(.secondary)
            if let name = appState.currentFile?.fileName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack {
            Image(systemName: "play.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No media loaded")
                .font(.headline)
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// NSViewRepresentable wrapper for AVPlayerView
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
