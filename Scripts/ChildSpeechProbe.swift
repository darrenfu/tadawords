import AVFoundation
import Foundation
import Speech

@available(macOS 26.0, *)
@main
struct ChildSpeechProbe {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw ProbeError.missingAudioPath
        }

        let audioURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let audioFile = try AVAudioFile(forReading: audioURL)
        let transcriber = SpeechTranscriber(
            locale: Locale(identifier: "en-US"),
            preset: .transcription
        )

        try await installAssetsIfNeeded(for: [transcriber])

        async let transcription = try transcriber.results.reduce(
            into: AttributedString()
        ) { accumulated, result in
            accumulated.append(result.text)
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let result = try await transcription
        print(String(result.characters))
    }

    private static func installAssetsIfNeeded(
        for modules: [any SpeechModule]
    ) async throws {
        let status = await AssetInventory.status(forModules: modules)
        guard status != .installed else { return }
        guard status != .unsupported else {
            throw ProbeError.unsupportedLocale
        }
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: modules
        ) {
            try await request.downloadAndInstall()
        }
    }
}

private enum ProbeError: Error {
    case missingAudioPath
    case unsupportedLocale
}
