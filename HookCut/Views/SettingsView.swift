import SwiftUI

/// Settings view accessible from the app menu (Cmd+,)
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var localWhisper = LocalWhisperService.shared
    @State private var showDeleteConfirmation = false
    @State private var templateToDelete: PromptTemplate?
    @State private var isDownloadingModel = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            highlightsTab
                .tabItem { Label("Highlights", systemImage: "wand.and.stars") }
            exportTab
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
            templatesTab
                .tabItem { Label("Templates", systemImage: "doc.text") }
        }
        .frame(width: 560, height: 520)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            // --- Transcription ---
            Section("Transcription") {
                Picker("Engine", selection: $appState.settings.transcriptionEngine) {
                    ForEach(TranscriptionEngine.allCases, id: \.self) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .onChange(of: appState.settings.transcriptionEngine) { appState.saveSettings() }

                if appState.settings.transcriptionEngine == .cloud {
                    SecureField("OpenAI API Key", text: $appState.settings.openAIAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: appState.settings.openAIAPIKey) { appState.saveSettings() }

                    if appState.settings.openAIAPIKey.isEmpty {
                        Label("Required for cloud transcription", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Picker("Model", selection: $appState.settings.localModelVariant) {
                        ForEach(LocalWhisperModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .onChange(of: appState.settings.localModelVariant) { appState.saveSettings() }

                    Text(appState.settings.localModelVariant.qualityDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // Model download status
                    modelStatusRow
                }
            }

            // --- Analysis ---
            Section("Analysis") {
                Picker("Provider", selection: $appState.settings.aiProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .onChange(of: appState.settings.aiProvider) { appState.saveSettings() }

                switch appState.settings.aiProvider {
                case .openAI:
                    if appState.settings.transcriptionEngine == .local {
                        // Only show key here if it's not already shown in transcription section
                        SecureField("OpenAI API Key", text: $appState.settings.openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: appState.settings.openAIAPIKey) { appState.saveSettings() }
                    }
                    if appState.settings.openAIAPIKey.isEmpty {
                        Label("Required for analysis", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                case .anthropic:
                    SecureField("Anthropic API Key", text: $appState.settings.anthropicAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: appState.settings.anthropicAPIKey) { appState.saveSettings() }
                    if appState.settings.anthropicAPIKey.isEmpty {
                        Label("Required for analysis", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                case .ollama:
                    TextField("Model", text: $appState.settings.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: appState.settings.ollamaModel) { appState.saveSettings() }
                    Text("Requires Ollama running locally. Recommended: qwen3:8b (16GB+) or qwen3:4b (8GB).")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // --- Fully local badge ---
            if appState.settings.transcriptionEngine == .local && appState.settings.aiProvider == .ollama {
                Section {
                    Label("Fully local — no API keys, no cloud, no cost", systemImage: "lock.shield")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.green)
                }
            }

            Section {
                Button("Reset All Settings to Defaults") {
                    appState.settings = .default
                    appState.saveSettings()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Model Status Row

    @ViewBuilder
    private var modelStatusRow: some View {
        switch localWhisper.modelState {
        case .notDownloaded:
            HStack {
                Label("Not downloaded", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download") {
                    downloadModel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isDownloadingModel)
            }
        case .downloading:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Downloading \(localWhisper.downloadingModelName)")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("\(Int(localWhisper.downloadProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: localWhisper.downloadProgress)
                HStack(spacing: 12) {
                    if !localWhisper.downloadedSize.isEmpty {
                        Text("\(localWhisper.downloadedSize) / \(localWhisper.totalSize)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if !localWhisper.downloadSpeed.isEmpty {
                        Text(localWhisper.downloadSpeed)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    if !localWhisper.downloadETA.isEmpty {
                        Text("ETA: \(localWhisper.downloadETA)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .ready:
            Label("Model ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .error(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Error", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Retry") { downloadModel() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }

    private func downloadModel() {
        isDownloadingModel = true
        Task {
            do {
                try await localWhisper.prepareModel(variant: appState.settings.localModelVariant)
            } catch {
                // Error state handled by localWhisper.modelState
            }
            isDownloadingModel = false
        }
    }

    // MARK: - Highlights Tab

    private var highlightsTab: some View {
        Form {
            Section("Highlight Count") {
                Toggle("Let AI decide", isOn: Binding(
                    get: { appState.settings.defaultHighlightCount == 0 },
                    set: { isAuto in
                        appState.settings.defaultHighlightCount = isAuto ? 0 : 15
                        appState.saveSettings()
                    }
                ))

                if appState.settings.defaultHighlightCount > 0 {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(appState.settings.defaultHighlightCount) },
                                set: { appState.settings.defaultHighlightCount = Int($0) }
                            ),
                            in: 5...30,
                            step: 1
                        )
                        Text("\(appState.settings.defaultHighlightCount)")
                            .frame(width: 30, alignment: .trailing)
                            .monospacedDigit()
                    }
                    .onChange(of: appState.settings.defaultHighlightCount) { appState.saveSettings() }
                } else {
                    Text("AI will choose the optimal number based on episode length and content density")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Highlight Types") {
                ForEach(HighlightType.allCases, id: \.self) { type in
                    let isLastEnabled = appState.settings.enabledHighlightTypes.count == 1
                        && appState.settings.enabledHighlightTypes.contains(type)
                    Toggle(type.displayName, isOn: Binding(
                        get: { appState.settings.enabledHighlightTypes.contains(type) },
                        set: { enabled in
                            if enabled {
                                appState.settings.enabledHighlightTypes.insert(type)
                            } else if appState.settings.enabledHighlightTypes.count > 1 {
                                appState.settings.enabledHighlightTypes.remove(type)
                            }
                            appState.saveSettings()
                        }
                    ))
                    .disabled(isLastEnabled)
                    .help(isLastEnabled ? "At least one highlight type must be enabled" : "")
                }
            }

            Section("Custom Prompt") {
                TextEditor(text: $appState.settings.customPromptAdditions)
                    .font(.body)
                    .frame(height: 60)
                    .onChange(of: appState.settings.customPromptAdditions) { appState.saveSettings() }
                Text("Additional instructions appended to the AI prompt during analysis")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Export Tab

    private var exportTab: some View {
        Form {
            Section("Default Format") {
                Picker("Export Format", selection: $appState.settings.defaultExportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .onChange(of: appState.settings.defaultExportFormat) { appState.saveSettings() }
            }

            Section("Gap Between Clips") {
                Picker("Gap Duration", selection: $appState.settings.defaultGapDuration) {
                    Text("0s").tag(0.0 as TimeInterval)
                    Text("0.5s").tag(0.5 as TimeInterval)
                    Text("1s").tag(1.0 as TimeInterval)
                    Text("2s").tag(2.0 as TimeInterval)
                }
                .onChange(of: appState.settings.defaultGapDuration) { appState.saveSettings() }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Templates Tab

    private var templatesTab: some View {
        VStack {
            HStack {
                Text("Active Template:")
                    .font(.subheadline.weight(.medium))
                Picker("", selection: Binding(
                    get: { appState.selectedTemplate?.id },
                    set: { id in
                        appState.selectedTemplate = appState.promptTemplates.first { $0.id == id }
                    }
                )) {
                    Text("None (default)").tag(nil as UUID?)
                    ForEach(appState.promptTemplates) { template in
                        Text(template.name).tag(template.id as UUID?)
                    }
                }
                .frame(width: 200)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            List {
                ForEach(Array(appState.promptTemplates.enumerated()), id: \.element.id) { index, template in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if template.isBuiltIn {
                                Text(template.name)
                                    .font(.headline)
                            } else {
                                TextField("Name", text: $appState.promptTemplates[index].name)
                                    .font(.headline)
                                    .textFieldStyle(.plain)
                            }
                            if template.isBuiltIn {
                                Text("Built-in")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.secondary.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            if appState.selectedTemplate?.id == template.id {
                                Text("Active")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            if !template.isBuiltIn {
                                Button(role: .destructive) {
                                    templateToDelete = template
                                    showDeleteConfirmation = true
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        if template.isBuiltIn {
                            Text(template.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("Description", text: $appState.promptTemplates[index].description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textFieldStyle(.plain)
                            TextEditor(text: $appState.promptTemplates[index].systemPromptOverride)
                                .font(.caption)
                                .frame(height: 60)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.separator, lineWidth: 1)
                                )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .alert("Delete Template?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let template = templateToDelete {
                        if appState.selectedTemplate?.id == template.id {
                            appState.selectedTemplate = nil
                        }
                        appState.promptTemplates.removeAll { $0.id == template.id }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }

            HStack {
                Spacer()
                Button {
                    let newTemplate = PromptTemplate(
                        name: "Custom Template",
                        description: "Edit this template",
                        systemPromptOverride: "Your custom prompt here..."
                    )
                    appState.promptTemplates.append(newTemplate)
                } label: {
                    Label("Add Template", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding()
        }
    }
}
