import SwiftUI

/// Settings view accessible from the app menu (Cmd+,)
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

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
        .frame(width: 520, height: 420)
    }

    // MARK: - API Keys Tab

    private var apiKeysTab: some View {
        Form {
            Section("OpenAI") {
                SecureField("API Key", text: $appState.settings.openAIAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: appState.settings.openAIAPIKey) { appState.saveSettings() }
            }

            Section("Anthropic") {
                SecureField("API Key", text: $appState.settings.anthropicAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: appState.settings.anthropicAPIKey) { appState.saveSettings() }
            }

            Section("Provider") {
                Picker("AI Provider", selection: $appState.settings.aiProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .onChange(of: appState.settings.aiProvider) { appState.saveSettings() }
            }

            if !hasActiveAPIKey {
                Label("Set an API key above to enable analysis", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Analysis Tab

    private var analysisTab: some View {
        Form {
            Section("Highlight Count") {
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
            }

            Section("Highlight Types") {
                ForEach(HighlightType.allCases, id: \.self) { type in
                    Toggle(type.displayName, isOn: Binding(
                        get: { appState.settings.enabledHighlightTypes.contains(type) },
                        set: { enabled in
                            if enabled {
                                appState.settings.enabledHighlightTypes.insert(type)
                            } else {
                                appState.settings.enabledHighlightTypes.remove(type)
                            }
                            appState.saveSettings()
                        }
                    ))
                }
            }

            Section("Custom Prompt") {
                TextEditor(text: $appState.settings.customPromptAdditions)
                    .font(.body)
                    .frame(height: 60)
                    .onChange(of: appState.settings.customPromptAdditions) { appState.saveSettings() }
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
            List {
                ForEach(appState.promptTemplates) { template in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(template.name)
                                .font(.headline)
                            if template.isBuiltIn {
                                Text("Built-in")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.secondary.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            if !template.isBuiltIn {
                                Button(role: .destructive) {
                                    appState.promptTemplates.removeAll { $0.id == template.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Text(template.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
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
        switch appState.settings.aiProvider {
        case .openAI: return !appState.settings.openAIAPIKey.isEmpty
        case .anthropic: return !appState.settings.anthropicAPIKey.isEmpty
        }
    }
}
