# CLAUDE.md

## Project: robot_lab-to

`robot_lab-to` ("takeover") is a robot_lab extension gem that runs a RobotLab Robot in an
autonomous loop toward a stated objective, committing one focused change per iteration.

## Commands

```bash
bundle install
bundle exec rake test          # all tests
bundle exec rake test_verbose  # verbose
bundle exec rake quality       # tests + rubocop + flog
bin/console                    # IRB shell
```

## Architecture

- **`Orchestrator`** — main loop: setup → iterate → **eval-gated** commit/rollback → stop
- **`Evals`** — orchestrator-owned scorers (`Evals.build` factory + `register_eval` registry). `Base` returns a `Score(gate_ok, improved, met_target, value, detail, output)`. `Null` (default, unscored), `Code` (measured: verify floor + `--measure`/`--target`, composes `Verifier`), `Prose` (pairwise LLM judge vs. the parent commit + optional `--floor`). Commit requires `gate_ok && improved`; the run stops on `met_target`. `Base#protected_paths` feeds `GraderLock`.
- **`Guards::GraderLock`** — always-on hook (independent of `--local-guards`) that refuses write/edit/bash on the eval's grader artifacts (spec + `--protect-path`); wired in `Orchestrator#build_robot`.
- **`SubmitResultTool`** — `RobotLab::Tool` the robot must call to report its result
- **`RequestDecisionTool`** — `RobotLab::Tool` the robot calls to escalate a choice (async HITL)
- **`IterationResult`** — `Data.define` value object (success, summary, key_changes, key_learnings, should_fully_stop)
- **`Decision`** — `Data.define` snapshot of one decision file (status, blocking, question, recommendation, resolution)
- **`DecisionManager`** — read/write/query decision files; parallels `NotesManager`
- **`CommitManager`** — all git ops via `Open3.capture3` (no shell interpolation); `checkout_branch` for resume
- **`NotesManager`** — cross-iteration memory file (notes.md); orchestrator writes, robot reads
- **`StopConditions`** — max_iterations, max_tokens, consecutive_failures, stop_when, **stop_on_plateau** (N iterations without improvement — the primary terminator for prose)
- **`Backoff`** — exponential (60 × 2^n seconds) + fixed `sleep_seconds` for decision polling; interruptible via `interrupt!`
- **`PromptBuilder`** — builds per-iteration system prompt with objective, notes, resolved decisions, a **score-feedback section** (best score / target / plateau warning for scored runs), and conditional sections
- **`JsonlLogger`** — JSONL event log with 100-event pre-init buffer
- **`ExitSummary`** — post-run metrics table and next-step commands
- **`CLI`** — `OptionParser`-based, binary `robot-to`; also `--resume` and the `decisions` subcommand
- **`Config`** — `MywayConfig::Base`, file `~/.config/robot_lab/to.yml`, prefix `ROBOT_LAB_TO_*`

## Key Pattern: Per-Iteration Robot

A fresh `RobotLab::Tool` (`SubmitResult`, plus `RequestDecision` when decisions are
enabled) and `RobotLab::Robot` are created per iteration. After `robot.run()`
returns, the orchestrator reads `submit_tool.captured_result` (nil → treated as
failure) and persists any `decision_tool.captured_requests` as decision files.

## Async Human-in-the-Loop (decision files)

When the robot hits a choice it must not make alone it calls `request_decision`;
the orchestrator writes a decision file with YAML front matter + a human-readable
body. Status lifecycle: `pending` → `resolved` (human edits the file) → `closed`
(resolution injected into a committed iteration). A **blocking** decision gates
the loop via `handle_blocking_decisions`: `decision_mode: wait` polls until
resolved (`decision_wait_poll` / `decision_timeout`); `decision_mode: exit` stops
with a `--resume` hint. See `decision_files_plan.md` in the parent workspace.
(Note: the workspace's `hitl_plan.md` is a *separate*, synchronous terminal-gate
design — not this feature.)

## Resume / cron

Each iteration writes `run.json` (`Run#to_h`). `robot-to --resume <run_id>` /
`RobotLab::To.resume` reloads it (`Run.load`), checks out the branch, and
re-enters the loop — so an external scheduler can drive one commit per tick.

## Run State

All run state lives in `.robot_lab_to/runs/<run_id>/` (added to `.git/info/exclude`):
- `notes.md` — cross-iteration log
- `run.log` — JSONL event log
- `run.json` — serialized `Run` snapshot (enables `--resume`)
- `decisions/d-*.md` — decision files

## Testing

Minitest. Git-dependent tests use `Dir.mktmpdir` with real `git init`.
Coverage gate: 95% line / 75% branch (`rake quality` also runs rubocop + flog + flay).
