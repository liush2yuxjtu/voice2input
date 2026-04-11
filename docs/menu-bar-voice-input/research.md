```text
  ┌────────────────────────────────────────────────────────────┐
  │ menu-bar voice input                                      │
  │ research: capture -> transcribe -> refine -> inject       │
  └────────────────────────────────────────────────────────────┘
```

# Research

## Architecture

- The repository starts empty, so the app needs a full Swift Package Manager executable target plus a manual `.app` bundle packaging step.
- The runtime is best modeled as an AppKit menu-bar app:
  - `NSApplication` + `NSStatusItem` for LSUIElement menu-bar lifecycle
  - `CGEventTap` for global `Fn` press/release interception and suppression
  - `Speech` + `AVAudioEngine` for streaming dictation
  - `NSPanel` + `NSVisualEffectView` + SwiftUI hosting for the floating capsule UI
  - Carbon Text Input Source APIs for temporary ASCII input-source switching
  - `NSPasteboard` + synthetic `Cmd+V` for text injection
  - `URLSession` against an OpenAI-compatible `chat/completions` endpoint for optional LLM refinement

## Data Flow

1. The global event tap watches `flagsChanged` events and filters on the `Fn` key (`kCGEventFlagMaskSecondaryFn` / keycode `63`).
2. On `Fn` down:
   - show the floating panel
   - start live audio capture
   - stream buffers into `SFSpeechAudioBufferRecognitionRequest`
   - compute audio RMS from the same buffers and push smoothed bar levels into the UI
3. While speaking:
   - partial transcripts update the label
   - the panel width grows within a bounded range as text length increases
4. On `Fn` up:
   - stop audio and finalize recognition
   - if LLM refinement is enabled and configured, keep the panel visible with a `Refining...` state and wait for the response
   - inject the final text into the focused field
5. Injection path:
   - snapshot current pasteboard contents
   - snapshot current input source
   - if the current input source is Chinese / Japanese / Korean, switch to an ASCII-capable source
   - set pasteboard string, synthesize `Cmd+V`, restore input source, restore pasteboard
6. Hide the panel with a short exit animation.

## Patterns And Conventions

- Keep AppKit lifecycle / permissions / status-menu orchestration in a central delegate.
- Keep capture, refinement, injection, and input-source handling in dedicated service objects.
- Use `UserDefaults` as the single persistence layer for selected language and LLM settings.
- Use SwiftUI only for the lightweight floating capsule body and the settings form; keep window creation in AppKit.
- Prefer small async APIs around long-running tasks (`finishRecognition`, `refine`, `inject`) so the coordinator can sequence them cleanly.

## Dependencies

- Apple frameworks:
  - `AppKit`
  - `SwiftUI`
  - `Speech`
  - `AVFoundation`
  - `Carbon`
  - `ApplicationServices`
- Tooling:
  - Swift 6.2 on macOS
  - SwiftPM executable target
  - `codesign` for ad-hoc signing of the generated app bundle

## Potential Impact Areas

- Event tap placement and callback filtering determine whether the `Fn` key can be suppressed without breaking the rest of the keyboard.
- Speech recognition finalization timing affects whether the last spoken words are lost on key release.
- Input-source restoration timing affects whether paste reaches the target app reliably under CJK IMEs.
- Pasteboard restoration must preserve preexisting rich data as much as practical.
- LSUIElement packaging depends on a correct `Info.plist` inside the generated `.app`.

## Edge Cases

- Missing Accessibility / Input Monitoring / Microphone / Speech Recognition permissions.
- Unsupported or temporarily unavailable locale in `SFSpeechRecognizer`.
- Releasing `Fn` before a recognizer callback has emitted any partial text.
- LLM timeout or malformed response: fall back to the raw transcript instead of blocking injection indefinitely.
- Empty transcript: do not inject anything.
- Current input source already ASCII: skip source switching.
- Current clipboard contains non-string multi-item payloads: restore all pasteboard items, not just plain text.

## Lessons From Last Run

- No prior implementation exists in this directory; the main lesson is to isolate all new files under `voice2input/` because the parent `/Users/m1/projects` worktree is already dirty in many unrelated paths.
