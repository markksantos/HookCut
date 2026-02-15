import SwiftUI
import AppKit

/// Modal sheet for export configuration and execution
struct ExportSheet: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exportFormat: ExportFormat = .fcpxml
    @State private var projectName: String = "HookCut Highlights"
    @State private var gapDuration: TimeInterval = 1.0
    @State private var includeMarkers: Bool = true
    @State private var isExporting: Bool = false
    @State private var exportSuccess: Bool = false
    @State private var exportedURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Highlights")
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

            // Configuration form
            Form {
                Section("Export Settings") {
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }

                    Text(formatDescription(exportFormat))
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    TextField("Project Name", text: $projectName)
                    if !isProjectNameValid {
                        Text("Project name cannot be empty or contain path separators")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Picker("Gap Between Clips", selection: $gapDuration) {
                        Text("None").tag(0.0 as TimeInterval)
                        Text("0.5 seconds").tag(0.5 as TimeInterval)
                        Text("1 second").tag(1.0 as TimeInterval)
                        Text("2 seconds").tag(2.0 as TimeInterval)
                    }

                    if exportFormat == .fcpxml {
                        Toggle("Include Markers", isOn: $includeMarkers)
                    }
                }

                Section("Preview") {
                    if let analysis = appState.analysis {
                        let approved = analysis.approvedHighlights
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(approved.count) clips to export")
                                .font(.callout.weight(.medium))
                            Text("Total duration: \(analysis.approvedDuration.mmss)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !approved.isEmpty {
                                Divider()
                                ForEach(approved.prefix(10)) { highlight in
                                    HStack {
                                        Text("#\(highlight.sequenceNumber)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24, alignment: .trailing)
                                        Text(highlight.text)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(highlight.duration.mmss)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                if approved.count > 10 {
                                    Text("... and \(approved.count - 10) more")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Action buttons
            HStack {
                if exportSuccess {
                    HStack(spacing: 8) {
                        Label("Export successful!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)

                        if exportedURL != nil {
                            Button("Show in Finder") {
                                if let url = exportedURL {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.callout)
                        }
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if !exportSuccess {
                    Button {
                        performExport()
                    } label: {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Export")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isExporting || !isProjectNameValid || (appState.analysis?.approvedHighlights.isEmpty ?? true))
                } else {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 580)
        .onAppear {
            exportFormat = appState.settings.defaultExportFormat
            gapDuration = appState.settings.defaultGapDuration
            if let fileName = appState.currentFile?.fileName {
                let name = (fileName as NSString).deletingPathExtension
                projectName = "\(name) - Highlights"
            }
        }
    }

    private var isProjectNameValid: Bool {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return !trimmed.isEmpty && trimmed.rangeOfCharacter(from: invalidChars) == nil
    }

    private func formatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .fcpxml: return "Final Cut Pro project with clips on timeline"
        case .premiereXML: return "Adobe Premiere Pro compatible XML interchange"
        case .edl: return "CMX 3600 EDL for DaVinci Resolve and other NLEs"
        case .csv: return "Spreadsheet with all highlight details"
        case .srt: return "Subtitle file with highlight timecodes"
        case .plainText: return "Full transcript with highlight markers"
        }
    }

    private func performExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "\(projectName).\(exportFormat.fileExtension)"
        panel.title = "Export Highlights"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            isExporting = true

            let config = ExportConfig(
                format: exportFormat,
                gapDuration: gapDuration,
                includeMarkers: includeMarkers,
                projectName: projectName
            )

            let success = viewModel.exportHighlights(format: exportFormat, config: config, to: url)

            isExporting = false
            exportSuccess = success
            if success {
                exportedURL = url
            }
        }
    }
}
