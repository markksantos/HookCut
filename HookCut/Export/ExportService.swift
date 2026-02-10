import Foundation

/// Routes export requests to the appropriate generator
struct ExportService: ExportServiceProtocol {

    private let fcpxmlGenerator = FCPXMLGenerator()
    private let premiereGenerator = PremiereXMLGenerator()
    private let edlGenerator = EDLGenerator()
    private let csvExporter = CSVExporter()
    private let srtExporter = SRTExporter()
    private let plainTextExporter = PlainTextExporter()

    func exportFCPXML(analysis: AnalysisResult, mediaFile: MediaFileInfo, config: ExportConfig) throws -> Data {
        try fcpxmlGenerator.generate(analysis: analysis, mediaFile: mediaFile, config: config)
    }

    func exportPremiereXML(analysis: AnalysisResult, mediaFile: MediaFileInfo, config: ExportConfig) throws -> Data {
        try premiereGenerator.generate(analysis: analysis, mediaFile: mediaFile, config: config)
    }

    func exportEDL(analysis: AnalysisResult, mediaFile: MediaFileInfo, config: ExportConfig) throws -> Data {
        try edlGenerator.generate(analysis: analysis, mediaFile: mediaFile, config: config)
    }

    func exportCSV(analysis: AnalysisResult, mediaFile: MediaFileInfo) throws -> Data {
        try csvExporter.generate(analysis: analysis, mediaFile: mediaFile)
    }

    func exportSRT(analysis: AnalysisResult) throws -> Data {
        try srtExporter.generate(analysis: analysis)
    }

    func exportPlainText(analysis: AnalysisResult, transcript: TranscriptionResult?) throws -> Data {
        try plainTextExporter.generate(analysis: analysis, transcript: transcript)
    }
}
