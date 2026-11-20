# Changelog

All notable changes to `robot_lab-to` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
and [Conventional Commits](https://www.conventionalcommits.org/) (see `COMMITS.md`).

## [Unreleased]

### Fixed

- **The iteration prompt names the working directory.** The only absolute path in the prompt was the notes file, so models inferred the project root from it and began each run reading paths that do not exist. A `## Working Directory` section now states the project root.
- **Example helper loads local models with an explicit context window.** `examples/common.rb` ran `lms load <model>` with LM Studio's default context (8192 tokens for some models), which the loop overflows inside the first iteration. It now loads with `RLTO_CONTEXT_LENGTH` tokens (default 32768) and reloads a model that is loaded with less.
- **The result and decision tools are exposed under the names the prompts use.** Every prompt told the model to call `submit_iteration_result` / `request_decision`, but the tools were registered as `robot_lab--to--tools--submit_result` and `robot_lab--to--tools--request_decision`, and the nudge message used a third name. Both tools now define `#name`.
- **A failed commit is no longer recorded as an improvement.** After a `CommitFailedError` the orchestrator still reset the failure counter, stored the uncommitted score as the one to beat, closed decisions, and could end the run as "target met".
- **Guard refusals name the real Edit parameter** (`old_text`, not `oldText`).
- CLI help: `--eval` lists `prose`; `--no-stream` and `--debug` describe what they do. The unknown-eval error lists `prose`.

## [0.6.1] - 2026-11-19

### Changed

- **Minimum Ruby raised to 4.0.9.** `required_ruby_version` is now `>= 4.0.9` (was `>= 3.2.0`), and a `.ruby-version` file pins development to 4.0.9.
- **Requires `robot_lab ~> 0.6`** (was `~> 0.3.0`). Verified against robot_lab 0.6.1 and ruby_llm 2.2.3; no code changes were needed.

## [0.2.8] - 2026-09-09

Released in lockstep with `robot_lab` core v0.2.8: this gem now resolves the released core gem from RubyGems instead of the local sibling checkout (local-path development remains available via `BUNDLE_GEMFILE=Gemfile.local`). Also in this release: reek pass completed, archspec added to the development bundle, and shared LM Studio example configuration extracted for the examples.

### Added

- **Human-in-the-loop decision files.** When the robot hits a choice it must not
  make autonomously, it calls `request_decision` and the orchestrator writes a
  decision file (situation, options, and its recommended "lean") under
  `runs/<id>/decisions/`. A human resolves it out-of-band by editing the file
  (`status: resolved` + `resolution:`); a later iteration reads the answer back.
  New `Decision` value object, `DecisionManager`, and `RequestDecision` tool.
- **Blocking decisions gate the loop.** `--decision-mode wait` (default) polls
  until the decision is resolved (`--decision-poll`, `--decision-timeout`);
  `--decision-mode exit` stops the run with a `--resume` hint. Disable with
  `--no-decisions`.
- **Resumable runs.** Run state is persisted to `run.json`; `robot-to --resume
  <run_id>` (or `RobotLab::To.resume`) continues a stopped run on the same
  branch — enabling cron/scheduled operation.
- **`decisions` subcommand.** `robot-to decisions [run_id]` lists pending and
  resolved decisions with their file paths.
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

## [0.2.7]

### Added

- **Evals: orchestrator-owned scoring.** An `Eval` scores each iteration's
  working tree and returns a `Score(gate_ok, improved, met_target, value, detail,
  output)` — the deciding authority for commit/rollback and, for measurable
  objectives, for when the run is done — instead of the robot's self-reported
  `should_fully_stop`. See [Evals](docs/concepts/evals.md).
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
  [Evals: Guarding the grader](docs/concepts/evals.md#guarding-the-grader-graderlock).
- **`write_guard` config (Ruby-only, default `true`).** Lets a `--local-guards`
  run opt out of `Guards::WriteGuard` (`write_guard: false`) so the robot can
  freely overwrite a file it is iteratively rewriting whole, e.g. a prose draft.
  See [Guardrails](docs/local-models/guardrails.md#write-guard).

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
