# Changelog

All notable changes to `robot_lab-to` are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project follows
[Conventional Commits](https://www.conventionalcommits.org/) (see `COMMITS.md`).

## Unreleased

### Added

- **Evals: orchestrator-owned scoring.** An `Eval` scores each iteration's
  working tree and returns a `Score(gate_ok, improved, met_target, value, detail,
  output)` — the deciding authority for commit/rollback and, for measurable
  objectives, for when the run is done — instead of the robot's self-reported
  `should_fully_stop`. See [Evals](../concepts/evals.md).
    - `Evals::Code` — measured/deterministic: the existing `--verify-command`
      floor plus an optional `--measure CMD` (a command printing a number,
      higher is better) and `--target FLOAT`. Fully backward compatible: with no
      `--measure`, behaves exactly like the original verify-only gate.
    - `Evals::Prose` — judged/pairwise: an LLM judge (`--judge-model`, defaults
      to `--model`) compares the working tree against the last committed
      version and rules it `better`/`worse`/`same`; an optional `--floor CMD`
      gates mechanizable checks before the judge is called.
    - `Evals::Null` — the default when nothing is configured; preserves the
      original "commit any reported success" behavior exactly.
    - `--eval NAME`, `--stop-on-plateau N`, `--[no-]require-improvement`, and
      Ruby-API extension points (`RobotLab::To.register_eval`, an instance
      responding to `#score`, or a bare proc, all passable as `eval:`).
    - `require_improvement` (default **true**) rolls back a gate-passing
      iteration that doesn't beat the parent's score, keeping the branch
      strictly descending.
    - `--stop-on-plateau N` — a new stop condition: abort after `N` iterations
      with no committed improvement. The primary terminator for `Evals::Prose`,
      which never sets a measurable target.
    - `PromptBuilder` **Score Feedback** section — for scored runs, tells each
      iteration's robot the best score committed so far, the target, and
      whether recent attempts plateaued, so each attempt is a hypothesis
      against the target instead of a blind guess.
- **`GraderLock` guard — grader lockdown.** Refuses `write`/`edit`/`bash` against
  an eval's own grading criteria (`Evals::Prose#protected_paths`'s `--spec`, plus
  any `--protect-path GLOB`), so the robot cannot "win" by rewriting the
  criteria it is scored against. Unlike the small-model guardrails, it is always
  installed when protected paths exist — independent of `--local-guards`. See
  [Evals: Guarding the grader](../concepts/evals.md#guarding-the-grader-graderlock).
- **`write_guard` config (Ruby-only, default `true`).** Lets a `--local-guards`
  run opt out of `Guards::WriteGuard` (`write_guard: false`) so the robot can
  freely overwrite a file it is iteratively rewriting whole, e.g. a prose draft.
  See [Guardrails](../local-models/guardrails.md#write-guard).
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
