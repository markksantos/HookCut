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

                    TextField("Project Name", text: $projectName)

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
                    Label("Export successful!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

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
                .disabled(isExporting || (appState.analysis?.approvedHighlights.isEmpty ?? true))
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

            viewModel.exportHighlights(format: exportFormat, config: config, to: url)

            isExporting = false
            exportSuccess = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }
}
