import SwiftUI

/// First-run welcome screen. Shown once (tracked via UserDefaults) to orient
/// new users and point them at Settings for API keys or fully-local mode.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    /// UserDefaults key flagging that the welcome screen has been seen.
    static let hasSeenWelcomeKey = "HookCutHasSeenWelcome"

    /// Whether the welcome screen should be presented on this launch.
    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: hasSeenWelcomeKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: hasSeenWelcomeKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    VStack(alignment: .leading, spacing: 16) {
                        step(
                            number: "1",
                            icon: "key.fill",
                            title: "Choose how you transcribe & analyze",
                            detail: "Use the OpenAI cloud (Whisper + GPT-4o) or run fully on-device with on-device Whisper and a local Ollama model — no API key, no cost. Set this up in Settings (⌘,)."
                        )
                        step(
                            number: "2",
                            icon: "arrow.down.doc.fill",
                            title: "Drop in a podcast or video",
                            detail: "Import an MP4, MOV, M4V, WAV, MP3, or M4A file. HookCut extracts the audio, transcribes it, labels speakers, and finds the best moments."
                        )
                        step(
                            number: "3",
                            icon: "wand.and.stars",
                            title: "Review highlights & export",
                            detail: "Approve, re-time, and reorder clips, then export an NLE-ready timeline: FCPXML, Premiere XML, EDL, SRT, CSV, or plain text."
                        )
                    }
                }
                .padding(28)
            }

            Divider()

            HStack {
                Button("Open Settings") {
                    finish()
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Get Started") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 540)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "scissors")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Welcome to HookCut")
                    .font(.largeTitle.weight(.bold))
            }
            Text("Find the best highlights in any podcast or video, then export them straight to your editor.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func step(number: String, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func finish() {
        WelcomeView.markSeen()
        dismiss()
    }
}
