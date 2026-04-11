import AVFoundation
import Foundation
import Speech

enum SpeechRecognitionError: LocalizedError {
    case recognizerUnavailable
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "当前语言的语音识别器不可用。"
        case .audioInputUnavailable:
            return "未检测到可用音频输入设备。"
        }
    }
}

final class SpeechRecognitionService {
    var onPartialTranscript: ((String) -> Void)?
    var onWaveformBars: (([CGFloat]) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let waveformGenerator = WaveformBarGenerator()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var finishContinuation: CheckedContinuation<String, Never>?
    private var finishTimeoutWorkItem: DispatchWorkItem?

    func start(locale: Locale) throws {
        cleanupSession()

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw SpeechRecognitionError.audioInputUnavailable
        }

        latestTranscript = ""
        waveformGenerator.reset()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handleRecognition(result: result, error: error)
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self, weak request] buffer, _ in
            request?.append(buffer)
            self?.handleWaveform(buffer: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        DispatchQueue.main.async { [weak self] in
            self?.onWaveformBars?(WaveformBarGenerator.idleBars)
        }
    }

    func finish() async -> String {
        guard recognitionRequest != nil || recognitionTask != nil else {
            return latestTranscript
        }

        let transcript = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            finishContinuation = continuation
            finishTimeoutWorkItem?.cancel()

            let timeout = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.resolveFinish(with: self.latestTranscript)
            }

            finishTimeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: timeout)
        }

        cleanupSession()
        return transcript
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            latestTranscript = result.bestTranscription.formattedString
            DispatchQueue.main.async { [weak self] in
                self?.onPartialTranscript?(result.bestTranscription.formattedString)
            }

            if result.isFinal {
                resolveFinish(with: result.bestTranscription.formattedString)
                return
            }
        }

        if error != nil {
            resolveFinish(with: latestTranscript)
        }
    }

    private func handleWaveform(buffer: AVAudioPCMBuffer) {
        let bars = waveformGenerator.makeBars(from: buffer)
        DispatchQueue.main.async { [weak self] in
            self?.onWaveformBars?(bars)
        }
    }

    private func resolveFinish(with transcript: String) {
        finishTimeoutWorkItem?.cancel()
        finishTimeoutWorkItem = nil

        let finalText = transcript
        let continuation = finishContinuation
        finishContinuation = nil

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        continuation?.resume(returning: finalText)
    }

    private func cleanupSession() {
        finishTimeoutWorkItem?.cancel()
        finishTimeoutWorkItem = nil
        finishContinuation = nil

        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

private final class WaveformBarGenerator {
    static let idleBars: [CGFloat] = [0.16, 0.24, 0.32, 0.24, 0.18]

    private let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private var envelope: CGFloat = 0.08

    func reset() {
        envelope = 0.08
    }

    func makeBars(from buffer: AVAudioPCMBuffer) -> [CGFloat] {
        let rms = rootMeanSquare(from: buffer)
        let decibels = max(-60, 20 * log10(max(rms, 0.000_1)))
        let normalized = max(0, min(1, (CGFloat(decibels) + 52) / 52))
        let smoothing: CGFloat = normalized > envelope ? 0.40 : 0.15
        envelope += (normalized - envelope) * smoothing

        return weights.map { weight in
            let jitter = CGFloat.random(in: 0.96 ... 1.04)
            return max(0.10, min(1.0, envelope * weight * jitter + 0.10))
        }
    }

    private func rootMeanSquare(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            return 0
        }

        let frameLength = Int(buffer.frameLength)
        if frameLength == 0 {
            return 0
        }

        let samples = channelData[0]
        var sum: Float = 0
        for index in 0 ..< frameLength {
            let sample = samples[index]
            sum += sample * sample
        }

        return sqrt(sum / Float(frameLength))
    }
}
