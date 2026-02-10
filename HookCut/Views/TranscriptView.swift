import SwiftUI

/// Right sidebar showing scrollable transcript with speaker labels and timestamps
struct TranscriptView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: AppViewModel
    @State private var searchText = ""
    @State private var autoScroll = true

    private var segments: [TranscriptionSegment] {
        guard let transcription = appState.transcription else { return [] }
        if searchText.isEmpty {
            return transcription.segments
        }
        return transcription.segments.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            segmentsList
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Transcript", systemImage: "text.quote")
                    .font(.headline)
                Spacer()
                Toggle(isOn: $autoScroll) {
                    Image(systemName: "arrow.down.to.line")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Auto-scroll to playback position")
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcript...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(6)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
    }

    private var segmentsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(segments) { segment in
                        segmentRow(segment)
                            .id(segment.id)
                            .onTapGesture {
                                viewModel.seek(to: segment.start)
                            }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.playbackTime) { _, newTime in
                if autoScroll, let target = nearestSegment(to: newTime) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(target.id, anchor: .center)
                    }
                }
            }
        }
    }

    private func segmentRow(_ segment: TranscriptionSegment) -> some View {
        let isHighlighted = isSegmentHighlighted(segment)
        let isCurrent = isSegmentCurrent(segment)

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let speaker = segment.speaker {
                        speakerBadge(speaker)
                    }
                    Text(segment.start.mmss)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Text(segment.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(segmentBackground(isHighlighted: isHighlighted, isCurrent: isCurrent))
        }
        .contentShape(Rectangle())
    }

    private func speakerBadge(_ name: String) -> some View {
        let color = speakerColor(for: name)
        return Text(name)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func segmentBackground(isHighlighted: Bool, isCurrent: Bool) -> Color {
        if isCurrent {
            return Color.accentColor.opacity(0.15)
        } else if isHighlighted {
            return Color.yellow.opacity(0.1)
        }
        return .clear
    }

    private func isSegmentHighlighted(_ segment: TranscriptionSegment) -> Bool {
        guard let highlights = appState.analysis?.highlights else { return false }
        return highlights.contains { h in
            h.startTime <= segment.end && h.endTime >= segment.start
        }
    }

    private func isSegmentCurrent(_ segment: TranscriptionSegment) -> Bool {
        viewModel.playbackTime >= segment.start && viewModel.playbackTime < segment.end
    }

    private func nearestSegment(to time: TimeInterval) -> TranscriptionSegment? {
        segments.last { $0.start <= time }
    }

    private func speakerColor(for name: String) -> Color {
        if let speakers = appState.analysis?.speakers,
           let speaker = speakers.first(where: { $0.name == name }) {
            return Color(hex: speaker.color) ?? .blue
        }
        return .blue
    }
}

// MARK: - Color from hex string

extension Color {
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }
        guard hexString.count == 6,
              let rgb = UInt64(hexString, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
