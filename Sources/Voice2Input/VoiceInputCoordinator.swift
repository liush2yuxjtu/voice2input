import Foundation

@MainActor
final class VoiceInputCoordinator {
    private let settings: AppSettings
    private let permissions: PermissionCenter
    private let speechService: SpeechRecognitionService
    private let overlayController: FloatingOverlayController
    private let textInjector: TextInjector
    private let refinementService: LLMRefinementService

    private var fnHeld = false
    private var isRecording = false
    private var isBusy = false

    init(
        settings: AppSettings,
        permissions: PermissionCenter,
        speechService: SpeechRecognitionService,
        overlayController: FloatingOverlayController,
        textInjector: TextInjector,
        refinementService: LLMRefinementService
    ) {
        self.settings = settings
        self.permissions = permissions
        self.speechService = speechService
        self.overlayController = overlayController
        self.textInjector = textInjector
        self.refinementService = refinementService

        speechService.onPartialTranscript = { [weak self] text in
            Task { @MainActor in
                self?.overlayController.update(text: text)
            }
        }

        speechService.onWaveformBars = { [weak self] bars in
            Task { @MainActor in
                self?.overlayController.updateBars(bars)
            }
        }
    }

    func handleFunctionKeyChange(_ isPressed: Bool) {
        fnHeld = isPressed
        if isPressed {
            startRecordingIfNeeded()
        } else {
            stopRecordingIfNeeded()
        }
    }

    private func startRecordingIfNeeded() {
        guard !isRecording, !isBusy else { return }
        isBusy = true

        Task {
            do {
                try await permissions.ensureReadyForCapture()
                try speechService.start(locale: settings.selectedLanguage.locale)
                overlayController.show(text: "开始说话…")
                isRecording = true
                isBusy = false

                if !fnHeld {
                    stopRecordingIfNeeded()
                }
            } catch {
                overlayController.flash(message: error.localizedDescription)
                isBusy = false
            }
        }
    }

    private func stopRecordingIfNeeded() {
        guard isRecording else { return }
        isRecording = false
        isBusy = true

        Task {
            let transcript = await speechService.finish()
            let rawText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if rawText.isEmpty {
                overlayController.hide()
                isBusy = false
                return
            }

            var finalText = rawText
            if settings.llmEnabled, settings.llmConfiguration.isComplete {
                overlayController.showRefining()
                do {
                    let refinedText = try await refinementService.refine(text: rawText, configuration: settings.llmConfiguration)
                    let trimmed = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        finalText = trimmed
                    }
                } catch {
                    finalText = rawText
                }
            }

            do {
                try await textInjector.inject(text: finalText)
            } catch {
                overlayController.flash(message: error.localizedDescription)
                isBusy = false
                return
            }

            overlayController.hide()
            isBusy = false
        }
    }
}
