```text
  ┌────────────────────────────────────────────────────────────┐
  │ report                                                    │
  │ build -> sign -> launch -> note remaining risks           │
  └────────────────────────────────────────────────────────────┘
```

# Report

## Summary

Implemented a macOS 14+ SwiftPM menu-bar voice input app from scratch under `voice2input/`:

- `Fn` hold/release capture flow with a suppressing global `CGEventTap`
- streaming Apple Speech recognition with default locale `zh-CN`
- language switching in the menu bar with `UserDefaults` persistence
- bottom-centered frameless capsule HUD using `NSPanel` + `NSVisualEffectView(.hudWindow)`
- real RMS-driven 5-bar waveform with smoothing, weighted center emphasis, and jitter
- conservative OpenAI-compatible LLM refinement with settings UI and enable toggle
- additional Anthropic-compatible LLM refinement support, including Kimi-style `ANTHROPIC_*` environment fallback
- Kimi `kimi-k2.5` refinement requests now send `"thinking": {"type": "disabled"}` to avoid long reasoning latency
- CJK-aware paste injection that temporarily switches to an ASCII input source before synthetic `Cmd+V`
- SwiftPM build + Makefile + local stable-signed `.app` bundle packaging

Incremental update:

- `AppSettings` now reads persisted values first, then falls back to environment variables:
  - `VOICE2INPUT_LLM_*`
  - `OPENAI_*`
  - `ANTHROPIC_BASE_URL`
  - `ANTHROPIC_AUTH_TOKEN`
  - `ANTHROPIC_MODEL`
- when the configuration looks like Kimi and no model is provided, it defaults to `kimi-k2.5`
- Anthropic-compatible endpoints are sent to `/v1/messages`, while OpenAI-compatible endpoints continue to use `/chat/completions`
- for `kimi-k2.5`, the client now explicitly disables thinking mode with `"thinking": {"type": "disabled"}`

## Files Added Or Updated

- `Package.swift`
- `Makefile`
- `App/Info.plist`
- `scripts/build_app.sh`
- `Sources/Voice2Input/*.swift`
- `docs/menu-bar-voice-input/plan.md`

## Verification

Commands run:

- `swift build`
- `make build`
- `codesign --verify --deep --strict build/Voice2Input.app`
- `open -n build/Voice2Input.app && sleep 2 && pgrep -x Voice2Input && pkill -x Voice2Input`

Observed results:

- debug build succeeded
- release build succeeded
- `build/Voice2Input.app` was created and ad-hoc signed
- `codesign --verify` passed
- launching the packaged app succeeded and the process stayed alive long enough to be detected

## Deviations

- Signing now uses a local stable identity (`Voice2Input Local Signing`) instead of ad-hoc signing, which avoids TCC permission churn across rebuilds on this machine. It is still not Developer ID signed or notarized.
- No automated UI-level validation was possible for live dictation, permission prompts, Fn suppression behavior, or paste injection into third-party apps because those depend on interactive macOS privacy approvals and a focused target application.

## Risks

- The first run still requires manual granting of Accessibility / Input Monitoring / Microphone / Speech Recognition permissions in System Settings.
- `Fn` suppression behavior can vary across macOS keyboard settings and hardware; it compiled and launches correctly, but the emoji-picker suppression path still needs manual confirmation on the target machine.
- The generic OpenAI-compatible client assumes a `/chat/completions` endpoint shape; providers with incompatible schemas will need a small adapter.

## Follow-Up

- Manually test the complete record -> transcribe -> refine -> inject flow in at least one native AppKit text field and one Chromium text field.
- If distribution outside the local machine matters, replace ad-hoc signing with a real Developer ID signing + notarization pipeline.
