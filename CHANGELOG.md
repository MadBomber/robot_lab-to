# Changelog

All notable changes to `robot_lab-to` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
and [Conventional Commits](https://www.conventionalcommits.org/) (see `COMMITS.md`).

## [Unreleased]

### Added

- **Local-model support.** Drive a local [Ollama](https://ollama.com) model
  end-to-end with `--local-guards` and `--no-stream`.
- **Built-in workspace tools** (`read`, `write`, `edit`, `bash`) attached to the
  per-iteration robot when `--local-guards` is set.
- **Small-model guardrails** — `write-guard`, `read-before-edit`, `checkpoint`,
  and `quality-monitor` `RobotLab::Hook` policies that make tool use safe for
  small local models.
- **`stream` setting** (`--no-stream`) — disable response streaming, required for
  Ollama tool calls; tokens are then accounted from each iteration's result.
- **Documentation site** (`docs/`, `mkdocs.yml`) plus a GitHub Pages deploy
  workflow.

### Fixed

- Tools were passed to `RobotLab.build` via `tools:` (a tool-name allowlist
  filter) instead of `local_tools:` (the instance list), so the
  `submit_iteration_result` tool was never attached to the robot. Now passed via
  `local_tools:`, with a regression test asserting the built robot exposes the
  tool.

## [0.1.0]

Initial release.

### Added

- Autonomous overnight loop (`Orchestrator`): a fresh robot per iteration, commit
  on success, `git reset --hard` on failure.
- `SubmitResult` tool and `IterationResult` value object.
- Cross-iteration memory via `notes.md` (`NotesManager`).
- Stop conditions: `--max-iterations`, `--max-tokens`,
  `--max-consecutive-failures`, and natural-language `--stop-when`.
- Independent verification gate (`--verify-command`, `Verifier`).
- Interruptible exponential `Backoff` for transient-error retries.
- JSONL event log (`JsonlLogger`) and post-run `ExitSummary`.
- `robot-to` CLI and `RobotLab::To.run` programmatic entry point.
- `Config` cascade (`myway_config`): defaults → user file → env → CLI.

[Unreleased]: https://github.com/MadBomber/robot_lab-to/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/MadBomber/robot_lab-to/releases/tag/v0.1.0
