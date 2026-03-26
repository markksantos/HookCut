import Foundation

// MARK: - Core Data Models shared across all modules

/// Represents the overall state of processing for a media file
enum ProcessingState: Equatable {
    case idle
    case extractingAudio(progress: Double)
    case transcribing(progress: Double, estimatedRemaining: TimeInterval?)
    case identifyingSpeakers
    case findingHighlights
    case complete
    case error(String)
}

/// Supported import file types
enum SupportedMediaType: String, CaseIterable {
    case mp4, mov, m4v, wav, mp3, m4a

    var isVideoFormat: Bool {
        switch self {
        case .mp4, .mov, .m4v: return true
        case .wav, .mp3, .m4a: return false
        }
    }

    var utType: String {
        switch self {
        case .mp4: return "public.mpeg-4"
        case .mov: return "com.apple.quicktime-movie"
        case .m4v: return "com.apple.m4v-video"
        case .wav: return "com.microsoft.waveform-audio"
        case .mp3: return "public.mp3"
        case .m4a: return "public.mpeg-4-audio"
        }
    }
}

/// Information about an imported media file
struct MediaFileInfo: Identifiable, Codable {
    let id: UUID
    let url: URL
    let fileName: String
    let fileSize: Int64
    let duration: TimeInterval
    let isVideoFile: Bool
    let videoWidth: Int?
    let videoHeight: Int?
    let frameRate: FrameRate?
    let codec: String?

    init(id: UUID = UUID(), url: URL, fileName: String, fileSize: Int64, duration: TimeInterval,
         isVideoFile: Bool, videoWidth: Int? = nil, videoHeight: Int? = nil,
         frameRate: FrameRate? = nil, codec: String? = nil) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.fileSize = fileSize
        self.duration = duration
        self.isVideoFile = isVideoFile
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.frameRate = frameRate
        self.codec = codec
    }
}

/// Standard frame rates used in video production
enum FrameRate: Codable, Equatable, CaseIterable {
    case fps23_976
    case fps24
    case fps25
    case fps29_97
    case fps30
    case fps59_94
    case fps60

    /// The actual frames per second value
    var fps: Double {
        switch self {
        case .fps23_976: return 24000.0 / 1001.0
        case .fps24: return 24.0
        case .fps25: return 25.0
        case .fps29_97: return 30000.0 / 1001.0
        case .fps30: return 30.0
        case .fps59_94: return 60000.0 / 1001.0
        case .fps60: return 60.0
        }
    }

    /// FCPXML frameDuration as rational time (numerator/denominator)
    var frameDuration: RationalTime {
        switch self {
        case .fps23_976: return RationalTime(numerator: 1001, denominator: 24000)
        case .fps24: return RationalTime(numerator: 100, denominator: 2400)
        case .fps25: return RationalTime(numerator: 100, denominator: 2500)
        case .fps29_97: return RationalTime(numerator: 1001, denominator: 30000)
        case .fps30: return RationalTime(numerator: 100, denominator: 3000)
        case .fps59_94: return RationalTime(numerator: 1001, denominator: 60000)
        case .fps60: return RationalTime(numerator: 100, denominator: 6000)
        }
    }

    /// Whether this is a drop-frame rate
    var isDropFrame: Bool {
        switch self {
        case .fps23_976, .fps29_97, .fps59_94: return true
        default: return false
        }
    }

    /// Detect frame rate from a raw FPS value
    static func detect(from rawFPS: Double) -> FrameRate {
        let rates: [(FrameRate, Double)] = [
            (.fps23_976, 23.976), (.fps24, 24.0), (.fps25, 25.0),
            (.fps29_97, 29.97), (.fps30, 30.0), (.fps59_94, 59.94), (.fps60, 60.0)
        ]
        return rates.min(by: { abs($0.1 - rawFPS) < abs($1.1 - rawFPS) })?.0 ?? .fps30
    }
}

/// Rational time representation for frame-accurate timecodes
struct RationalTime: Codable, Equatable {
    let numerator: Int
    let denominator: Int

    init(numerator: Int, denominator: Int) {
        precondition(denominator > 0, "RationalTime denominator must be positive")
        self.numerator = numerator
        self.denominator = denominator
    }

    var seconds: Double {
        Double(numerator) / Double(denominator)
    }

    /// FCPXML string representation e.g. "1001/30000s"
    var fcpxmlString: String {
        "\(numerator)/\(denominator)s"
    }

    /// Reduce fraction using GCD to prevent numerator bloat
    var reduced: RationalTime {
        let divisor = Self.gcd(abs(numerator), abs(denominator))
        guard divisor > 1 else { return self }
        return RationalTime(numerator: numerator / divisor, denominator: denominator / divisor)
    }

    /// Create rational time from seconds, snapped to nearest frame boundary
    static func fromSeconds(_ seconds: Double, frameRate: FrameRate) -> RationalTime {
        let fd = frameRate.frameDuration
        let frameCount = Int(round(seconds / fd.seconds))
        return RationalTime(
            numerator: frameCount * fd.numerator,
            denominator: fd.denominator
        )
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}

// MARK: - Transcription Models

/// A single word with its timestamp from Whisper
struct TranscriptionWord: Codable, Identifiable {
    let id: UUID
    let word: String
    let start: TimeInterval
    let end: TimeInterval

    init(id: UUID = UUID(), word: String, start: TimeInterval, end: TimeInterval) {
        self.id = id
        self.word = word
        self.start = start
        self.end = end
    }
}

/// A segment of transcription (usually a sentence or phrase)
struct TranscriptionSegment: Codable, Identifiable {
    let id: UUID
    var speaker: String?
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let words: [TranscriptionWord]

    init(id: UUID = UUID(), speaker: String? = nil, text: String,
         start: TimeInterval, end: TimeInterval, words: [TranscriptionWord] = []) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.start = start
        self.end = end
        self.words = words
    }
}

/// Complete transcription result
struct TranscriptionResult: Codable {
    let segments: [TranscriptionSegment]
    let fullText: String
    let duration: TimeInterval
    let language: String?
}

// MARK: - Speaker Models

/// A speaker identified in the content
struct Speaker: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var role: String?
    var color: String // hex color for UI badge

    init(id: UUID = UUID(), name: String, role: String? = nil, color: String = "#007AFF") {
        self.id = id
        self.name = name
        self.role = role
        self.color = color
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Speaker, rhs: Speaker) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Highlight Models

/// Types of highlights the AI can detect
enum HighlightType: String, Codable, CaseIterable {
    case oneLiner = "one-liner"
    case cliffhanger = "cliffhanger"
    case hotTake = "hot-take"
    case emotional = "emotional"
    case insight = "insight"
    case humor = "humor"

    var displayName: String {
        switch self {
        case .oneLiner: return "One-Liner"
        case .cliffhanger: return "Cliffhanger"
        case .hotTake: return "Hot Take"
        case .emotional: return "Emotional"
        case .insight: return "Insight"
        case .humor: return "Humor"
        }
    }

    var badgeColor: String {
        switch self {
        case .oneLiner: return "#FF6B35"
        case .cliffhanger: return "#9B59B6"
        case .hotTake: return "#E74C3C"
        case .emotional: return "#3498DB"
        case .insight: return "#2ECC71"
        case .humor: return "#F39C12"
        }
    }
}

/// A single highlight found by AI
struct Highlight: Codable, Identifiable {
    let id: UUID
    var sequenceNumber: Int
    var type: HighlightType
    var rating: Int // 1-5 stars
    var text: String
    var context: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var speakerId: UUID
    var isApproved: Bool

    init(id: UUID = UUID(), sequenceNumber: Int, type: HighlightType, rating: Int,
         text: String, context: String, startTime: TimeInterval, endTime: TimeInterval,
         speakerId: UUID, isApproved: Bool = true) {
        self.id = id
        self.sequenceNumber = sequenceNumber
        self.type = type
        self.rating = max(1, min(5, rating))
        self.text = text
        self.context = context
        self.startTime = startTime
        self.endTime = max(startTime + 0.1, endTime) // Ensure positive duration
        self.speakerId = speakerId
        self.isApproved = isApproved
    }

    var duration: TimeInterval {
        endTime - startTime
    }
}

/// Complete AI analysis result
struct AnalysisResult: Codable {
    let episodeSummary: String
    let speakers: [Speaker]
    var highlights: [Highlight]
    let suggestedTeaserOrder: [Int] // sequence numbers

    /// Approved highlights only
    var approvedHighlights: [Highlight] {
        highlights.filter { $0.isApproved }
    }

    /// Total duration of approved highlights
    var approvedDuration: TimeInterval {
        approvedHighlights.reduce(0) { $0 + $1.duration }
    }
}

// MARK: - Export Models

/// Available export formats
enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case fcpxml = "FCPXML"
    case premiereXML = "Premiere XML"
    case edl = "EDL"
    case csv = "CSV"
    case srt = "SRT"
    case plainText = "Plain Text"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .fcpxml: return "fcpxml"
        case .premiereXML: return "xml"
        case .edl: return "edl"
        case .csv: return "csv"
        case .srt: return "srt"
        case .plainText: return "txt"
        }
    }
}

/// Export configuration
struct ExportConfig: Codable {
    var format: ExportFormat
    var gapDuration: TimeInterval // seconds between clips
    var includeMarkers: Bool
    var projectName: String

    init(format: ExportFormat = .fcpxml, gapDuration: TimeInterval = 1.0,
         includeMarkers: Bool = true, projectName: String = "HookCut Highlights") {
        self.format = format
        self.gapDuration = gapDuration
        self.includeMarkers = includeMarkers
        self.projectName = projectName
    }
}

// MARK: - Settings Models

/// AI provider selection
enum AIProvider: String, Codable, CaseIterable {
    case openAI = "OpenAI (GPT-4o)"
    case anthropic = "Anthropic (Claude)"
    case ollama = "Local (Ollama)"
}

/// How highlights are sorted in the review panel
enum HighlightSortOrder: String, Codable, CaseIterable {
    case chronological = "Chronological"
    case aiSuggested = "AI Suggested"
    case byRating = "By Rating"
    case bySpeaker = "By Speaker"
}

/// Transcription engine: cloud (OpenAI Whisper API) or local (WhisperKit on-device)
enum TranscriptionEngine: String, Codable, CaseIterable {
    case cloud = "Cloud (OpenAI)"
    case local = "Local (On-Device)"
}

/// Available local Whisper model variants
enum LocalWhisperModel: String, Codable, CaseIterable, Identifiable {
    case tiny = "openai_whisper-tiny.en"
    case base = "openai_whisper-base.en"
    case small = "openai_whisper-small.en"
    case large = "openai_whisper-large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (~40 MB)"
        case .base: return "Base (~75 MB)"
        case .small: return "Small (~216 MB)"
        case .large: return "Large v3 (~947 MB)"
        }
    }

    var qualityDescription: String {
        switch self {
        case .tiny: return "Fastest, basic quality"
        case .base: return "Fast, good quality"
        case .small: return "Balanced speed and quality"
        case .large: return "Best quality, slower"
        }
    }
}

/// App settings
struct AppSettings: Codable {
    var openAIAPIKey: String
    var anthropicAPIKey: String
    var aiProvider: AIProvider
    var ollamaModel: String
    var transcriptionEngine: TranscriptionEngine
    var localModelVariant: LocalWhisperModel
    var defaultHighlightCount: Int // 5-30
    var enabledHighlightTypes: Set<HighlightType>
    var defaultExportFormat: ExportFormat
    var defaultGapDuration: TimeInterval
    var customPromptAdditions: String
    var targetDurationSeconds: Int // 0 = unconstrained
    var sortOrder: HighlightSortOrder

    static var `default`: AppSettings {
        AppSettings(
            openAIAPIKey: "",
            anthropicAPIKey: "",
            aiProvider: .openAI,
            ollamaModel: "qwen3:8b",
            transcriptionEngine: .cloud,
            localModelVariant: .small,
            defaultHighlightCount: 15,
            enabledHighlightTypes: Set(HighlightType.allCases),
            defaultExportFormat: .fcpxml,
            defaultGapDuration: 1.0,
            customPromptAdditions: "",
            targetDurationSeconds: 0,
            sortOrder: .chronological
        )
    }
}

// MARK: - Template Prompt Models

/// Predefined prompt templates for different use cases
struct PromptTemplate: Codable, Identifiable {
    let id: UUID
    var name: String
    var description: String
    var systemPromptOverride: String
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, description: String,
         systemPromptOverride: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.systemPromptOverride = systemPromptOverride
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Cost Estimation

struct CostEstimate {
    let transcriptionCost: Double // Whisper cost
    let analysisCost: Double // GPT-4o / Claude cost
    let totalCost: Double
    let audioDurationMinutes: Double

    /// Estimate cost based on audio duration
    static func estimate(durationSeconds: TimeInterval) -> CostEstimate {
        let minutes = durationSeconds / 60.0
        // Whisper: $0.006 per minute
        let whisperCost = minutes * 0.006
        // GPT-4o analysis: ~$0.0025 per minute of transcript (rough estimate)
        let analysisCost = minutes * 0.0025
        return CostEstimate(
            transcriptionCost: whisperCost,
            analysisCost: analysisCost,
            totalCost: whisperCost + analysisCost,
            audioDurationMinutes: minutes
        )
    }
}

// MARK: - Session Persistence

/// Saved session data for restore without re-processing
struct SessionData: Codable {
    let mediaURL: URL
    let mediaFileName: String
    let transcription: TranscriptionResult
    let analysis: AnalysisResult
    let savedAt: Date

    /// Sanitize a file name by replacing path-unsafe characters
    private static func sanitizedFileName(_ name: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return name.unicodeScalars
            .map { unsafe.contains($0) ? "_" : String($0) }
            .joined()
    }

    static func save(_ data: SessionData, for fileName: String) {
        let safe = sanitizedFileName(fileName)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("HookCut/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(safe).json")
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: file)
        }
    }

    static func load(for fileName: String) -> SessionData? {
        let safe = sanitizedFileName(fileName)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("HookCut/Sessions", isDirectory: true)
        let file = dir.appendingPathComponent("\(safe).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SessionData.self, from: data)
    }
}

// MARK: - Batch Processing

/// Status for batch processing multiple files
struct BatchItem: Identifiable {
    let id: UUID
    let fileInfo: MediaFileInfo
    var state: ProcessingState
    var transcription: TranscriptionResult?
    var analysis: AnalysisResult?

    init(id: UUID = UUID(), fileInfo: MediaFileInfo, state: ProcessingState = .idle) {
        self.id = id
        self.fileInfo = fileInfo
        self.state = state
    }
}
