import SwiftUI

@main
struct HookCutApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 650)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 900)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

/// Central app state that coordinates between all modules
@MainActor
class AppState: ObservableObject {
    @Published var currentFile: MediaFileInfo?
    @Published var processingState: ProcessingState = .idle
    @Published var transcription: TranscriptionResult?
    @Published var analysis: AnalysisResult?
    @Published var settings: AppSettings
    @Published var batchItems: [BatchItem] = []
    @Published var selectedHighlightId: UUID?
    @Published var promptTemplates: [PromptTemplate] = PromptTemplate.builtInTemplates
    @Published var selectedTemplate: PromptTemplate?

    /// The currently accessed security-scoped URL (must be released when done)
    private var securityScopedURL: URL?

    /// Begin accessing a security-scoped resource and track it for later release
    func beginAccessingFile(_ url: URL) -> URL {
        // Release any previously held resource
        stopAccessingCurrentFile()
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }
        return url
    }

    /// Stop accessing the current security-scoped resource
    func stopAccessingCurrentFile() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    // Services
    var transcriptionService: TranscriptionServiceProtocol?
    var exportService: ExportServiceProtocol?

    init() {
        self.settings = SettingsManager.load()
        self.transcriptionService = TranscriptionService()
        self.exportService = ExportService()
    }

    func saveSettings() {
        SettingsManager.save(settings)
    }
}

// MARK: - Service Protocols (implemented by respective teammates)

/// Protocol for transcription pipeline (Teammate 1)
protocol TranscriptionServiceProtocol {
    func extractAudio(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> URL
    func transcribe(audioURL: URL, apiKey: String, progressHandler: @escaping (Double) -> Void) async throws -> TranscriptionResult
    func transcribeLocally(audioURL: URL, progressHandler: @escaping (Double) -> Void) async throws -> TranscriptionResult
    func identifySpeakers(transcript: TranscriptionResult, apiKey: String, provider: AIProvider, anthropicKey: String?, ollamaModel: String?) async throws -> TranscriptionResult
    func findHighlights(transcript: TranscriptionResult, settings: AppSettings, template: PromptTemplate?) async throws -> AnalysisResult
}

/// Protocol for export pipeline (Teammate 2)
protocol ExportServiceProtocol {
    func exportFCPXML(analysis: AnalysisResult, mediaFile: MediaFileInfo, config: ExportConfig) throws -> Data
    func exportPremiereXML(analysis: AnalysisResult, mediaFile: MediaFileInfo, config: ExportConfig) throws -> Data
    func exportEDL(analysis: AnalysisResult, mediaFile: MediaFileInfo, config: ExportConfig) throws -> Data
    func exportCSV(analysis: AnalysisResult, mediaFile: MediaFileInfo) throws -> Data
    func exportSRT(analysis: AnalysisResult) throws -> Data
    func exportPlainText(analysis: AnalysisResult, transcript: TranscriptionResult?) throws -> Data
}

/// Protocol for settings persistence
protocol SettingsManagerProtocol {
    static func load() -> AppSettings
    static func save(_ settings: AppSettings)
}

// MARK: - Settings Manager

struct SettingsManager: SettingsManagerProtocol {
    private static let key = "HookCutSettings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    static func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Built-in Prompt Templates

extension PromptTemplate {
    static var builtInTemplates: [PromptTemplate] {
        [
            PromptTemplate(
                name: "Podcast Teaser",
                description: "Find hooks and cliffhangers for a trailer/teaser intro",
                systemPromptOverride: "Focus on moments that create maximum curiosity and tension. Prioritize cliffhangers, surprising reveals, and statements that make viewers want to watch the full episode. Think: trailer moments.",
                isBuiltIn: true
            ),
            PromptTemplate(
                name: "Best Quotes",
                description: "Standalone quotable moments for social media clips",
                systemPromptOverride: "Find moments that work as standalone clips for social media. Each quote should make sense without any context. Prioritize punchy one-liners, wisdom, and shareable insights. Think: clips that get screenshotted and shared.",
                isBuiltIn: true
            ),
            PromptTemplate(
                name: "Key Takeaways",
                description: "Educational and informational highlights",
                systemPromptOverride: "Focus on the most valuable educational content. Find key lessons, actionable advice, important facts, and expert insights. Think: the notes someone would take if studying this content.",
                isBuiltIn: true
            ),
            PromptTemplate(
                name: "Funny Moments",
                description: "Humor and lighthearted clips",
                systemPromptOverride: "Find the funniest moments: jokes that land, witty comebacks, amusing stories, unexpected humor, and moments where everyone laughs. Prioritize genuine comedy over mild amusement.",
                isBuiltIn: true
            ),
            PromptTemplate(
                name: "Controversial Takes",
                description: "Spicy opinions and debates",
                systemPromptOverride: "Find the most polarizing, surprising, or debate-sparking moments. Look for hot takes, disagreements between speakers, contrarian views, and statements that would generate comments and discussion.",
                isBuiltIn: true
            ),
        ]
    }
}

// MARK: - Codable conformance for Set<HighlightType>

extension Set<HighlightType>: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        let types = rawValue.split(separator: ",").compactMap { HighlightType(rawValue: String($0)) }
        self = Set(types)
    }

    public var rawValue: String {
        self.map(\.rawValue).joined(separator: ",")
    }
}
