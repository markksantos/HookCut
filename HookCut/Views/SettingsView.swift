import SwiftUI

/// Settings view accessible from the app menu (Cmd+,)
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showDeleteConfirmation = false
    @State private var templateToDelete: PromptTemplate?

    var body: some View {
        TabView {
            apiKeysTab
                .tabItem { Label("API Keys", systemImage: "key") }
            analysisTab
                .tabItem { Label("Analysis", systemImage: "wand.and.stars") }
            exportTab
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
            templatesTab
                .tabItem { Label("Templates", systemImage: "doc.text") }
        }
        .frame(width: 520, height: 440)
    }

    // MARK: - API Keys Tab

    private var apiKeysTab: some View {
        Form {
            Section("OpenAI") {
                SecureField("API Key", text: $appState.settings.openAIAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: appState.settings.openAIAPIKey) { appState.saveSettings() }
                Text("Required for transcription (Whisper). Also used for analysis if selected.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Anthropic") {
                SecureField("API Key", text: $appState.settings.anthropicAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: appState.settings.anthropicAPIKey) { appState.saveSettings() }
                Text("Used for speaker identification and highlight detection when selected.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Provider") {
                Picker("AI Provider", selection: $appState.settings.aiProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .onChange(of: appState.settings.aiProvider) { appState.saveSettings() }
                Text("OpenAI is always used for transcription. This controls which AI is used for analysis.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !hasActiveAPIKey {
                VStack(alignment: .leading, spacing: 2) {
                    if appState.settings.openAIAPIKey.isEmpty {
                        Label("OpenAI API key required for Whisper transcription", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                    if appState.settings.aiProvider == .anthropic && appState.settings.anthropicAPIKey.isEmpty {
                        Label("Anthropic API key required (selected as AI provider)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Analysis Tab

    private var analysisTab: some View {
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

    // MARK: - Templates Tab

    private var templatesTab: some View {
        VStack {
            // Active template selector
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

    // MARK: - Helpers

    private var hasActiveAPIKey: Bool {
        // OpenAI key is always required for Whisper transcription
        guard !appState.settings.openAIAPIKey.isEmpty else { return false }
        // If using Anthropic for analysis, also need an Anthropic key
        if appState.settings.aiProvider == .anthropic {
            return !appState.settings.anthropicAPIKey.isEmpty
        }
        return true
    }
}
