```text
  ┌────────────────────────────────────────────────────────────┐
  │ review                                                    │
  │ plan coverage -> report coverage -> residual risks        │
  └────────────────────────────────────────────────────────────┘
```

# Review

## Plan Coverage

- All four phases in `plan.md` are marked complete.
- The implemented code covers the planned package scaffold, menu-bar lifecycle, event tap, speech pipeline, floating HUD, LLM settings, and text injection path.

## Report Coverage

- `report.md` records the actual build, signing, launch validation, and the main caveats around permissions and notarization.
- Verification commands in the report line up with commands actually run in this turn.

## Mismatches

- The plan described an ASCII-source fallback preference of `ABC/US`; the implementation prefers `ABC/US` first and falls back to the current ASCII-capable source only if those are unavailable.
- The plan assumed only `report.md` as required output; additional post-hook notes were added here for Boris-style closure.

## Open Risks

- Live interactive validation is still manual for Fn suppression, speech permission prompts, and cross-app paste reliability.
- Gatekeeper acceptance is still unresolved because the app is ad-hoc signed rather than Developer ID signed and notarized.

## Follow-Up Actions

- Test the full flow in TextEdit, Notes, and a Chromium-based app after granting permissions.
- If the app will be distributed, add a real signing identity and notarization step to the build script or CI.
