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

- **`Orchestrator`** — main loop: setup → iterate → commit/rollback → stop
- **`SubmitResultTool`** — `RobotLab::Tool` the robot must call to report its result
- **`IterationResult`** — `Data.define` value object (success, summary, key_changes, key_learnings, should_fully_stop)
- **`CommitManager`** — all git ops via `Open3.capture3` (no shell interpolation)
- **`NotesManager`** — cross-iteration memory file (notes.md); orchestrator writes, robot reads
- **`StopConditions`** — max_iterations, max_tokens, consecutive_failures, stop_when
- **`Backoff`** — exponential (60 × 2^n seconds), interruptible via `interrupt!`
- **`PromptBuilder`** — builds per-iteration system prompt with objective, notes, and conditional sections
- **`JsonlLogger`** — JSONL event log with 100-event pre-init buffer
- **`ExitSummary`** — post-run metrics table and next-step commands
- **`CLI`** — `OptionParser`-based, binary `robot-to`
- **`Config`** — `MywayConfig::Base`, file `~/.config/robot_lab/to.yml`, prefix `ROBOT_LAB_TO_*`

## Key Pattern: Per-Iteration Robot

A fresh `RobotLab::Tool` (`SubmitResult`) and `RobotLab::Robot` are created per iteration.
After `robot.run()` returns, the orchestrator reads `submit_tool.captured_result`.
Nil result → treated as failure (robot never called the tool).

## Run State

All run state lives in `.robot_lab_to/runs/<run_id>/`:
- `notes.md` — cross-iteration log (added to `.git/info/exclude`)
- `run.log` — JSONL event log

## Testing

Minitest. Git-dependent tests use `Dir.mktmpdir` with real `git init`.
