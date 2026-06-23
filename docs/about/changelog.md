# Changelog

All notable changes to `robot_lab-to` are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project follows
[Conventional Commits](https://www.conventionalcommits.org/) (see `COMMITS.md`).

## Unreleased

### Added

- **Local-model support.** Drive a local Ollama model end-to-end with
  `--local-guards` and `--no-stream`. See [Local Models](../local-models/index.md).
- **Built-in workspace tools** (`read`, `write`, `edit`, `bash`) attached when
  `--local-guards` is set. See [Built-in Tools](../local-models/tools.md).
- **Small-model guardrails** — `write-guard`, `read-before-edit`, `checkpoint`,
  and `quality-monitor` hooks. See [Guardrails](../local-models/guardrails.md).
- **`stream` setting** (`--no-stream`) — disable response streaming, required for
  Ollama tool calls; tokens are then accounted from each iteration's result.
- This documentation site.

### Fixed

- Tools were passed to `RobotLab.build` via `tools:` (a name allowlist filter)
  instead of `local_tools:` (the instance list), so the `submit_iteration_result`
  tool was never attached to the robot. Now passed via `local_tools:`, with a
  regression test asserting the built robot exposes the tool.

## 0.1.0

Initial release.

### Added

- Autonomous overnight loop (`Orchestrator`): fresh robot per iteration, commit on
  success, `git reset --hard` on failure.
- `SubmitResult` tool and `IterationResult` value object.
- Cross-iteration memory via `notes.md` (`NotesManager`).
- Stop conditions: `--max-iterations`, `--max-tokens`,
  `--max-consecutive-failures`, and natural-language `--stop-when`.
- Independent verification gate (`--verify-command`, `Verifier`).
- Interruptible exponential `Backoff` for transient-error retries.
- JSONL event log (`JsonlLogger`) and post-run `ExitSummary`.
- `robot-to` CLI and `RobotLab::To.run` programmatic entry point.
- `Config` cascade (`myway_config`): defaults → user file → env → CLI.
