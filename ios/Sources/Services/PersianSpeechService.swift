import AVFoundation
import Combine
import Foundation

@MainActor
final class PersianSpeechService: ObservableObject {
    @Published private(set) var isPersianVoiceAvailable: Bool

    private let synthesizer = AVSpeechSynthesizer()
    private let persianVoice: AVSpeechSynthesisVoice?

    init() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let voice = voices.first { $0.language.lowercased().hasPrefix("fa") }
        persianVoice = voice
        isPersianVoiceAvailable = voice != nil
    }

    func speak(_ text: String) {
        guard let persianVoice, !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = persianVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
