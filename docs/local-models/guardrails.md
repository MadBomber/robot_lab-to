# Guardrails

The guardrails are `RobotLab::Hook` policies that intercept the robot's tool calls
to catch the mistakes small local models reliably make. They are enabled with
`--local-guards` and are no-ops you'd never notice with a frontier model — they
exist for the 8–35B local case.

They are adapted from the open-source [`little-coder`](https://github.com/itayinbarr/little-coder)
harness, whose core finding is that a guard-rich scaffold raised the same small
model's coding-benchmark score by **2.4×**. The harness, not the model, does the
heavy lifting.

## The four guards

### write-guard

**Problem:** small models love to "fix" a file by rewriting the whole thing with
`write`, destroying everything they didn't think to include.

**Policy:** refuse `write` to a file that already exists and tell the model to use
`edit` instead. It also normalizes a root-bare path like `/foo.rb` (a common
small-model mistake) to the working directory.

Implemented as `around_tool_call` (to block) + `before_tool_call` (to normalize
the path).

**Opting out:** `write-guard` is the one guard in the set that can get in the way
of *legitimate* work — a robot iteratively rewriting a whole prose draft each
pass wants plain `write`, not a forced `edit`. Set `write_guard: false` (Ruby-only,
default `true`; no CLI flag) to drop it from the installed set while keeping
`read-before-edit`, `checkpoint`, and `quality-monitor`:

```ruby
RobotLab::To.run(objective, local_guards: true, write_guard: false)
```

Internally this calls `Guards.install(robot, run:, except: [Guards::WriteGuard])`.

### read-before-edit

**Problem:** models fire `edit` with an `old_text` they never actually saw —
guessing the file's contents — which either fails the exact-match (a wasted turn)
or, worse, matches the wrong span.

**Policy:** refuse `edit` on any file that wasn't `read` this run, directing the
model to read it first. A successful `read`, `edit`, or `write` marks the file as
known. The read-set is per-run state.

### checkpoint

**Problem:** a single botched edit can spoil otherwise-good work within an
iteration.

**Policy:** before the first `write`/`edit` of a file, snapshot its current bytes
(first-write-wins) to `runs/<run_id>/checkpoints/`. Files that didn't exist get an
`.absent` sentinel. This is finer-grained than the orchestrator's
`git reset --hard` rollback — it survives *within* an iteration. Best-effort:
checkpointing never raises into the tool path.

### quality-monitor

**Problem:** a small model can get stuck repeating the exact same tool call, which
on an unattended overnight run silently burns the entire token budget.

**Policy:** detect the same `name` + arguments called on consecutive turns. After
a couple of consecutive repeats it raises a `QualityError`, which the orchestrator
handles like any iteration error — roll back, record the reason in `notes.md`, and
move on. This is the load-bearing guard for long unattended runs.

!!! info "Empty-response handling is intentionally left out"
    An earlier version also flagged "empty" responses, but RobotLab fires the
    generation hook once per *run* (not per turn), so that check false-tripped on
    legitimate tool-using turns. Empty / no-progress is handled instead by the
    orchestrator's existing nudge → "did not submit" path, which recovers
    gracefully rather than hard-erroring.

!!! info "A fifth guard, `GraderLock`, is not part of this set"
    `Guards::GraderLock` (`guards/grader_lock.rb`) lives alongside these four but
    is **not** gated by `--local-guards` — it locks an [eval's](../concepts/evals.md)
    grading criteria (a spec, a floor script, `--protect-path` globs) from robot
    edits, and is installed whenever such paths exist, regardless of model size.
    A frontier model can reward-hack its own grading criteria just as easily as a
    small model can mangle a file. See
    [Evals: Guarding the grader](../concepts/evals.md#guarding-the-grader-graderlock).

## How they're registered

`Guards.install(robot, run:)` registers all four on the per-iteration robot. The
orchestrator calls it from `build_robot` only when `local_guards` is enabled:

```ruby
robot = RobotLab.build(..., local_tools: iteration_tools(submit_tool))
RobotLab::To::Guards.install(robot, run: @run) if @config.local_guards?
```

## Per-run state

RobotLab builds a fresh hook context per tool call with no shared metadata across
calls, so cross-call guard state (the read-set, the checkpoint-set, the loop
tracker) can't live in the hook context. Because `robot_lab-to` runs each
iteration in its own thread, the guards keep that state in a thread-local
`RunStore` — the same idiom `robot_lab-audit` uses for run IDs. It's reset at the
start of each run.

## Relationship to the git rollback

The guards and the orchestrator's git rollback are complementary, at two
granularities:

| Layer | Granularity | Recovers |
|-------|-------------|----------|
| `checkpoint` guard | a single file, within an iteration | a botched individual edit |
| `git reset --hard` | the whole working tree, per iteration | a failed iteration |

---

Next: [Architecture](../reference/architecture.md).
