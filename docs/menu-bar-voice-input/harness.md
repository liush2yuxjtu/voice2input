```text
  ┌────────────────────────────────────────────────────────────┐
  │ harness                                                   │
  │ source coverage -> keyword summary -> reusable hooks      │
  └────────────────────────────────────────────────────────────┘
```

# Harness

## Source Coverage

Scanned real local Claude history sources:

- `/Users/m1/.claude/history.jsonl`
- multiple files under `/Users/m1/.claude/projects/**/*.jsonl`

The quick scan sampled project histories from prior planner / workflow-heavy sessions and counted workflow-related keywords across the first batch of discovered project logs.

## Keyword Summary

Observed counts from the sampled history scan:

- `hook`: 190
- `harness`: 434
- `workflow`: 219
- `AGENTS.md`: 527
- `CLAUDE.md`: 22
- `report.md`: 79
- `plan.md`: 149

## Candidate Harness Patterns

- A documentation-first delivery pattern is heavily reinforced: research / plan / report artifacts appear repeatedly and are worth keeping even for greenfield repos.
- Rule files such as `AGENTS.md` appear much more often than `CLAUDE.md`, suggesting repo-local rule loading is the stable anchor.
- Harness / hook language appears often enough to justify preserving a lightweight post-run checklist after implementation: build, sign, launch, risk note.

## Evidence Snippets

Real history excerpts observed during the scan:

- `~/.claude/history.jsonl` contains a direct request mentioning `report.md`.
- sampled project queue records under `~/.claude/projects/...jsonl` include planner-oriented content with explicit workflow structure and staged execution text.

## Recommended Reusable Hooks

- After greenfield implementations, always run `swift build`, release packaging, signature verification, and one launch smoke test before writing `report.md`.
- Keep a small post-run checklist template:
  `build result -> package result -> signature state -> launch smoke -> manual risks`
- When a repo starts empty, create process docs first so the later report can compare intent vs execution without reconstructing context from memory.
