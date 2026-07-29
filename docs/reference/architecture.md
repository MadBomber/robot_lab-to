# Architecture

`robot_lab-to` is a thin, well-separated orchestration layer over RobotLab. The
`Orchestrator` owns the loop and the git history; everything else is a
single-purpose collaborator it drives.

![robot-to architecture](../assets/architecture.svg)

## Component map

| Component | File | Responsibility |
|-----------|------|----------------|
| `CLI` | `cli.rb` | `OptionParser`-based `robot-to` entry point. |
| `Config` | `config.rb` | `MywayConfig::Base` settings cascade. |
| `Orchestrator` | `orchestrator.rb` | The main loop: setup → iterate → eval-gated commit/rollback → stop → finalize. |
| `PromptBuilder` | `prompt_builder.rb` | Builds each iteration's system prompt (objective, notes, task, submit, repair, score feedback, stop-when). |
| `Run` | `run.rb` | Mutable run-state value object (iteration, counters, tokens, timing, paths, `last_score_value`, `iterations_since_improvement`). |
| `SubmitResult` | `tools/submit_result.rb` | Tool the robot calls to report its result. |
| `IterationResult` | `iteration_result.rb` | `Data.define` value object for a submitted result. |
| `CommitManager` | `commit_manager.rb` | All git operations via `Open3` (no shell interpolation); also diffs the working tree vs. a ref for `Evals::Prose`. |
| `NotesManager` | `notes_manager.rb` | Reads/writes the cross-iteration `notes.md`. |
| `StopConditions` | `stop_conditions.rb` | Evaluates iterations / tokens / failures / plateau / stop-when. |
| `Verifier` | `verifier.rb` | Low-level command runner (timeout, process-group kill); composed by `Evals::Code`. |
| `Backoff` | `backoff.rb` | Interruptible exponential backoff for retries. |
| `JsonlLogger` | `jsonl_logger.rb` | Append-only JSONL event log with a pre-init buffer. |
| `ExitSummary` | `exit_summary.rb` | Prints the post-run report. |
| `AtomicFile` | `atomic_file.rb` | Atomic writes/appends for `notes.md`. |

## Evals — orchestrator-owned scoring

The eval subsystem generalizes the verify-command gate into a pluggable, scalar
scoring loop. See [Evals](../concepts/evals.md) for the full behavioral model —
this table is the file map.

| Component | File | Responsibility |
|-----------|------|-----------------|
| `Evals::Score` | `evals/score.rb` | `Data.define(gate_ok, improved, met_target, value, detail, output)` — the verdict for one iteration. |
| `Evals::Context` | `evals/context.rb` | `Data.define(work_dir, previous_ref, previous_value, objective, iteration)` handed to every eval. |
| `Evals::Base` | `evals/base.rb` | Abstract eval; `#score(ctx)` and `#protected_paths` (default `[]`). |
| `Evals::Null` | `evals/null.rb` | Default when nothing is configured: always `gate_ok: true, improved: true, met_target: false`. |
| `Evals::Code` | `evals/code.rb` | Measured/deterministic: `--verify-command` floor + optional `--measure`/`--target`. Composes `Verifier`. |
| `Evals::Prose` | `evals/prose.rb` | Judged/pairwise: an LLM judge compares the working tree vs. the parent commit; optional `--floor`. `met_target` always `false`. |
| `Evals::ProcEval` | `evals/factory.rb` | Wraps a bare proc passed as `eval:` so it responds to `#score`. |
| `Evals.build` / `Evals.from_name` | `evals/factory.rb` | Resolves `config.eval` (instance / proc / registered Symbol / `"code"` / `"null"` / `"prose"` / `nil`) into an eval. |
| `Guards::GraderLock` | `guards/grader_lock.rb` | Always-on `RobotLab::Hook` (independent of `--local-guards`) refusing write/edit/bash on an eval's `protected_paths` + `--protect-path`. |

## Local-model layer

These components are active only when `--local-guards` is set:

| Component | File | Responsibility |
|-----------|------|----------------|
| `Tools::FileTool` | `tools/file_tool.rb` | Base class giving file tools short names. |
| `Tools::Read/Write/Edit/Bash` | `tools/*.rb` | Built-in workspace tools. |
| `Guards` | `guards.rb` | Registers all guards on a robot via `install(robot, run:, except:)`. |
| `Guards::WriteGuard` | `guards/write_guard.rb` | Refuse `write` on existing files; normalize paths. Excludable per-run via `Config#write_guard = false` (Ruby-only, default `true`) — useful when the robot is iteratively rewriting a whole file, e.g. a prose draft. |
| `Guards::ReadBeforeEdit` | `guards/read_before_edit.rb` | Refuse `edit` before `read`. |
| `Guards::Checkpoint` | `guards/checkpoint.rb` | Snapshot files before mutation. |
| `Guards::QualityMonitor` | `guards/quality_monitor.rb` | Detect repeated-tool-call loops. |
| `Guards::RunStore` | `guards/run_store.rb` | Thread-local per-run guard state. |
| `Guards::PathResolution` | `guards/path_resolution.rb` | Pure path helpers shared by the guards. |

See [Guardrails](../local-models/guardrails.md) and
[Built-in Tools](../local-models/tools.md).

## Key design decisions

### Fresh robot per iteration

Each iteration constructs a new `RobotLab::Robot`. There is no shared chat history;
continuity is carried entirely by `notes.md`. This keeps every iteration a clean,
independent attempt and bounds context growth.

### The orchestrator owns git, the robot owns work

The robot never commits. It makes changes and reports a result; the orchestrator
decides whether to commit (gated by the configured eval) or roll back. This
separation is what makes the git history trustworthy.

### The eval, not the robot, decides "better" and "done"

`should_fully_stop` and a claimed `success: true` are the robot grading its own
homework. `Evals::Base#score` is the orchestrator-owned authority instead:
`gate_ok`/`improved` decide commit vs. rollback, and `met_target` — not the
robot's self-report — decides when a measurable objective is done. `--stop-when`
remains as a fallback for objectives an eval can't measure. See
[Evals](../concepts/evals.md).

### Grader lockdown is separate from the local-model guards

`Guards::GraderLock` protects the eval's own criteria (a spec, a floor script,
`--protect-path` globs) from robot edits. It is wired in unconditionally when
protected paths exist, unlike the small-model guardrail set
(`Guards.install`, gated by `--local-guards`) — a frontier model can reward-hack
its grading criteria just as easily as a small one can mangle a file.

### Tools attach via `local_tools:`

Tool *instances* are passed to `RobotLab.build` as `local_tools:`. (RobotLab's
`tools:` parameter is a name *allowlist filter*, not an instance list — passing
instances there silently attaches nothing.) A regression test asserts the built
robot actually exposes the submit tool, guarding against that class of mistake.

### Streaming is optional

By default the robot streams, enabling per-chunk token accounting and mid-stream
budget enforcement. Local Ollama models run non-streaming (`stream: false`), so
tokens are accounted from each iteration's result and the budget is enforced at
iteration boundaries. See [Ollama Setup](../local-models/ollama.md#streaming-and-tool-calls).

### Interruptible by design

Signal handlers, the backoff sleep, and the per-iteration runner thread all
cooperate so a `SIGINT`/`SIGTERM` stops the run promptly and cleanly, with the
exit summary still printed.

## Run lifecycle (control flow)

```
To.run(objective, **opts)
└─ Orchestrator#run
   ├─ setup_run            branch, notes, run dir, collaborators (incl. Evals.build)
   ├─ main_loop
   │  └─ per iteration:
   │     ├─ build fresh robot (PromptBuilder + tools [+ guards] [+ GraderLock])
   │     ├─ robot.run  → SubmitResult captured
   │     ├─ nudge if not submitted
   │     ├─ evaluate (Eval#score) if success reported
   │     │  ├─ gate fails  → repair_until_gate (R2), else reset --hard
   │     │  ├─ gate ok, not improved → reset --hard ([NO IMPROVEMENT])
   │     │  └─ gate ok, improved → commit; check met_target?
   │     ├─ NotesManager append
   │     └─ StopConditions check (incl. plateau)
   └─ finalize_run         JSONL close, ExitSummary
```

---

Next: [Changelog](../about/changelog.md).
