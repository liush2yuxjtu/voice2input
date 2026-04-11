```text
  ┌────────────────────────────────────────────────────────────┐
  │ plan                                                      │
  │ fn hold -> record -> transcribe -> refine -> paste        │
  └────────────────────────────────────────────────────────────┘
```

# Plan

## Overview

Build a macOS 14+ LSUIElement menu-bar app in Swift with SwiftPM. The app listens for a held `Fn` key globally, performs streaming speech recognition in the selected language, shows a bottom-centered capsule HUD with live waveform and transcript, optionally refines the recognized text through a conservative OpenAI-compatible LLM, then pastes the final text into the currently focused field while temporarily forcing an ASCII input source if the active IME is CJK.

## Phases

### Phase 1

- [x] Create the SwiftPM package, app bundle metadata, and Makefile packaging flow.
- [x] Add a menu-bar app delegate, status menu, persisted settings, and permissions helpers.

### Phase 2

- [x] Implement global `Fn` interception with a suppressing `CGEventTap`.
- [x] Implement streaming speech capture with `AVAudioEngine` + `SFSpeechAudioBufferRecognitionRequest`.
- [x] Convert live RMS audio into smoothed 5-bar waveform levels.

### Phase 3

- [x] Implement the frameless floating capsule panel with entry / resize / exit animations.
- [x] Implement input-source switching, pasteboard snapshotting, and synthetic `Cmd+V` injection.
- [x] Implement OpenAI-compatible LLM refinement plus settings UI.

### Phase 4

- [x] Wire the full release flow: finalize transcript -> optional LLM -> inject -> restore state -> dismiss HUD.
- [x] Build and run validation, then fix compile or logic issues.
- [x] Update this plan with completion marks and write `report.md`.

## Tasks

- [x] Add `Package.swift` targeting macOS 14 and an executable product.
- [x] Add `App/Info.plist` with `LSUIElement`, microphone usage, and speech recognition usage strings.
- [x] Add `scripts/build_app.sh` to package `.build/release/Voice2Input` into `build/Voice2Input.app` and ad-hoc sign it.
- [x] Add `Makefile` targets: `build`, `run`, `install`, `clean`.
- [x] Define persisted language options: English, Simplified Chinese, Traditional Chinese, Japanese, Korean; default `zh-CN`.
- [x] Build the status menu with language switching and an `LLM Refinement` submenu.
- [x] Implement a settings window with API base URL, API key, model, `Test`, and `Save`.
- [x] Implement a `CGEventTap` on `flagsChanged` filtering `Fn` key transitions and returning `nil` to swallow those events.
- [x] Implement `SpeechRecognitionService.start()` and `finish()` around live audio buffers and partial callbacks.
- [x] Implement RMS normalization, envelope smoothing, weighted bar scaling, and per-bar jitter.
- [x] Implement `FloatingOverlayController` using `NSPanel(nonactivatingPanel)` and `NSVisualEffectView(material: .hudWindow)`.
- [x] Implement elastic text-width measurement and animated panel frame updates.
- [x] Implement input-source inspection via Carbon TIS APIs and temporary ASCII switching for CJK IMEs.
- [x] Implement pasteboard snapshot / restore and synthetic `Cmd+V`.
- [x] Implement conservative LLM correction over `chat/completions` with strict “return unchanged when already correct” behavior.
- [x] Orchestrate busy-state handling so overlapping recording / injection sessions do not race.

## Code Snippets

```swift
if fnPressed {
    overlay.show(text: "开始说话…")
    try speech.start(locale: selectedLanguage.locale)
} else {
    let transcript = await speech.finish()
    let finalText = await maybeRefine(transcript)
    try await injector.inject(text: finalText)
    overlay.dismiss()
}
```

```swift
let normalized = max(0, min(1, (decibels + 52) / 52))
let envelope = target > current
    ? current + (target - current) * 0.40
    : current + (target - current) * 0.15
```

```swift
let shouldSwitch = currentSource.languages.contains { ["zh", "ja", "ko"].contains(prefix($0)) }
let asciiSource = TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue()
```

## Files To Modify

- `/Users/m1/projects/voice2input/Package.swift`
- `/Users/m1/projects/voice2input/Makefile`
- `/Users/m1/projects/voice2input/App/Info.plist`
- `/Users/m1/projects/voice2input/scripts/build_app.sh`
- `/Users/m1/projects/voice2input/Sources/Voice2Input/main.swift`
- `/Users/m1/projects/voice2input/Sources/Voice2Input/*.swift`
- `/Users/m1/projects/voice2input/docs/menu-bar-voice-input/report.md`

## Reference Implementations

- Apple Speech streaming pattern: `SFSpeechAudioBufferRecognitionRequest` fed by `AVAudioEngine` input taps.
- Carbon Text Input Source pattern: `TISCopyCurrentKeyboardInputSource`, `TISCopyCurrentASCIICapableKeyboardInputSource`, `TISSelectInputSource`.
- Event-tap pattern: `kCGEventFlagsChanged` for modifier keys, including `Fn`.

## Post-Hook Expectations

- `report.md` should capture what was implemented, how it was verified, permission/runtime caveats, and any remaining risks.
- If post-hook documents are added later, they should only summarize plan coverage and reusable packaging/test patterns rather than duplicate implementation detail.
