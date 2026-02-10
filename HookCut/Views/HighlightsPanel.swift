import SwiftUI

/// Bottom panel showing highlight cards with speaker filtering and approval controls
struct HighlightsPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedSpeakerId: UUID?
    @State private var expandedHighlightId: UUID?

    private var speakers: [Speaker] {
        appState.analysis?.speakers ?? []
    }

    private var filteredHighlights: [Highlight] {
        guard let analysis = appState.analysis else { return [] }
        var highlights = analysis.highlights
        if let speakerId = selectedSpeakerId {
            highlights = highlights.filter { $0.speakerId == speakerId }
        }
        if viewModel.minimumRating > 1 {
            highlights = highlights.filter { $0.rating >= viewModel.minimumRating }
        }
        return highlights
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            filterBar
            HStack(spacing: 0) {
                speakerSidebar
                    .frame(width: 160)
                Divider()
                highlightsGrid
            }
            statusBar
        }
        .onKeyPress(.rightArrow) { navigateHighlight(direction: 1); return .handled }
        .onKeyPress(.leftArrow) { navigateHighlight(direction: -1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "e")) { _ in approveCurrentHighlight(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "r")) { _ in rejectCurrentHighlight(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "p")) { _ in playCurrentHighlight(); return .handled }
    }

    // MARK: - Filter & Sort Bar

    private var filterBar: some View {
        HStack(spacing: 16) {
            // Sort order
            HStack(spacing: 4) {
                Text("Sort:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { appState.settings.sortOrder },
                    set: { order in
                        appState.settings.sortOrder = order
                        viewModel.sortHighlights(by: order)
                    }
                )) {
                    ForEach(HighlightSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            // Rating filter
            HStack(spacing: 4) {
                Text("Min rating:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $viewModel.minimumRating) {
                    Text("All").tag(1)
                    Text("2+").tag(2)
                    Text("3+").tag(3)
                    Text("4+").tag(4)
                    Text("5").tag(5)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Spacer()

            // Assembled preview
            if viewModel.isPreviewingAssembled {
                HStack(spacing: 8) {
                    Text("Preview: clip \(viewModel.currentPreviewIndex + 1)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    Button {
                        viewModel.stopAssembledPreview()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
                }
            } else {
                Button {
                    viewModel.playAssembledPreview()
                } label: {
                    Label("Preview All", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.approvedClipsCount == 0)
                .help("Play all approved clips back-to-back")
            }

            // Smart auto-fit
            if appState.settings.targetDurationSeconds > 0 {
                Button {
                    viewModel.autoFitToTargetDuration()
                } label: {
                    Label("Auto-Fit", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Auto-select best clips to fit target duration")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Speaker Sidebar

    private var speakerSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Speakers")
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.top, 8)

            Button {
                selectedSpeakerId = nil
            } label: {
                HStack {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 8, height: 8)
                    Text("All Speakers")
                        .font(.callout)
                    Spacer()
                    Text("\(appState.analysis?.highlights.count ?? 0)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selectedSpeakerId == nil ? Color.accentColor.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            ForEach(speakers) { speaker in
                Button {
                    selectedSpeakerId = speaker.id
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: speaker.color) ?? .blue)
                            .frame(width: 8, height: 8)
                        Text(speaker.name)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        let count = appState.analysis?.highlights.filter { $0.speakerId == speaker.id }.count ?? 0
                        Text("\(count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(selectedSpeakerId == speaker.id ? Color.accentColor.opacity(0.1) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack {
                Button("Select All") {
                    selectAllHighlights(approved: true)
                }
                Button("Deselect All") {
                    selectAllHighlights(approved: false)
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(.background.secondary)
    }

    // MARK: - Highlights Grid

    private var highlightsGrid: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredHighlights) { highlight in
                    highlightCard(highlight)
                }
            }
            .padding(10)
        }
    }

    private func highlightCard(_ highlight: Highlight) -> some View {
        let speaker = speakers.first { $0.id == highlight.speakerId }
        let speakerColor = Color(hex: speaker?.color ?? "#007AFF") ?? .blue
        let isExpanded = expandedHighlightId == highlight.id

        let isSelected = appState.selectedHighlightId == highlight.id
        return VStack(alignment: .leading, spacing: 6) {
            // Top row: speaker + type + rating
            HStack {
                // Speaker badge
                Text(speaker?.name ?? "Unknown")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(speakerColor.opacity(0.2))
                    .foregroundStyle(speakerColor)
                    .clipShape(Capsule())

                // Type badge
                Text(highlight.type.displayName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: highlight.type.badgeColor)?.opacity(0.2) ?? .gray.opacity(0.2))
                    .foregroundStyle(Color(hex: highlight.type.badgeColor) ?? .gray)
                    .clipShape(Capsule())

                Spacer()

                // Star rating
                starRating(highlight)
            }

            // Quote text
            Text(highlight.text)
                .font(.callout)
                .lineLimit(isExpanded ? nil : 3)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedHighlightId = isExpanded ? nil : highlight.id
                    }
                }

            // Context
            if !highlight.context.isEmpty {
                Text(highlight.context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Bottom row: time + controls
            HStack(spacing: 12) {
                // Time display
                HStack(spacing: 4) {
                    Text(highlight.startTime.mmss)
                    Text("-")
                    Text(highlight.endTime.mmss)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                // Time adjustment steppers
                HStack(spacing: 2) {
                    Button {
                        viewModel.adjustHighlightTime(highlight, startDelta: -0.5, endDelta: 0)
                    } label: {
                        Image(systemName: "minus")
                    }
                    Text("Start")
                        .font(.caption2)
                    Button {
                        viewModel.adjustHighlightTime(highlight, startDelta: 0.5, endDelta: 0)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                .font(.caption2)
                .buttonStyle(.borderless)

                HStack(spacing: 2) {
                    Button {
                        viewModel.adjustHighlightTime(highlight, startDelta: 0, endDelta: -0.5)
                    } label: {
                        Image(systemName: "minus")
                    }
                    Text("End")
                        .font(.caption2)
                    Button {
                        viewModel.adjustHighlightTime(highlight, startDelta: 0, endDelta: 0.5)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                .font(.caption2)
                .buttonStyle(.borderless)

                Spacer()

                // Play button
                Button {
                    viewModel.playHighlight(highlight)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("Preview this highlight")

                // Approve / Reject
                Button {
                    viewModel.approveHighlight(highlight)
                } label: {
                    Image(systemName: highlight.isApproved ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(highlight.isApproved ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help("Approve")

                Button {
                    viewModel.rejectHighlight(highlight)
                } label: {
                    Image(systemName: highlight.isApproved ? "xmark.circle" : "xmark.circle.fill")
                        .foregroundStyle(highlight.isApproved ? Color.secondary : Color.red)
                }
                .buttonStyle(.borderless)
                .help("Reject")
            }
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(highlight.isApproved ? 1.0 : 0.6)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .onTapGesture {
            appState.selectedHighlightId = highlight.id
        }
    }

    private func starRating(_ highlight: Highlight) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= highlight.rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(star <= highlight.rating ? .yellow : .secondary.opacity(0.3))
                    .onTapGesture {
                        viewModel.updateHighlightRating(highlight, rating: star)
                    }
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            let approved = viewModel.approvedClipsCount
            let duration = viewModel.approvedDuration

            Text("Approved: \(approved) clips")
                .font(.callout)

            Text("|")
                .foregroundStyle(.quaternary)

            Text("Total duration: \(duration.mmss)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                viewModel.showExportSheet = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(approved == 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Helpers

    private func selectAllHighlights(approved: Bool) {
        guard var analysis = appState.analysis else { return }
        for i in analysis.highlights.indices {
            if let speakerId = selectedSpeakerId {
                if analysis.highlights[i].speakerId == speakerId {
                    analysis.highlights[i].isApproved = approved
                }
            } else {
                analysis.highlights[i].isApproved = approved
            }
        }
        appState.analysis = analysis
    }

    private func navigateHighlight(direction: Int) {
        let highlights = filteredHighlights
        guard !highlights.isEmpty else { return }

        if let currentId = appState.selectedHighlightId,
           let currentIndex = highlights.firstIndex(where: { $0.id == currentId }) {
            let newIndex = max(0, min(highlights.count - 1, currentIndex + direction))
            appState.selectedHighlightId = highlights[newIndex].id
        } else {
            appState.selectedHighlightId = highlights.first?.id
        }
    }

    private func approveCurrentHighlight() {
        guard let id = appState.selectedHighlightId,
              let highlight = filteredHighlights.first(where: { $0.id == id }) else { return }
        viewModel.approveHighlight(highlight)
    }

    private func rejectCurrentHighlight() {
        guard let id = appState.selectedHighlightId,
              let highlight = filteredHighlights.first(where: { $0.id == id }) else { return }
        viewModel.rejectHighlight(highlight)
    }

    private func playCurrentHighlight() {
        guard let id = appState.selectedHighlightId,
              let highlight = filteredHighlights.first(where: { $0.id == id }) else { return }
        viewModel.playHighlight(highlight)
    }
}
