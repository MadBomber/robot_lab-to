# Anatomy of a Run

A single `robot-to` invocation produces a git branch, a run directory, and a
post-run summary. This page walks through each artifact.

## The branch

On startup the orchestrator:

1. Verifies `HEAD` exists (at least one commit).
2. Creates a branch named `robot-to/<slug>-<timestamp>` from the current `HEAD`.
3. Records the `base_commit` SHA so the exit summary can diff the whole run.

Every successful iteration is committed onto this branch. Your original branch is
untouched.

```
* 6a7137c robot-to 2: add docstring and confirm behavior   ← iteration 2
* 5810ae0 robot-to 1: create greeter.rb with greet method  ← iteration 1
* 362b8d9 initial                                           ← base_commit
```

### Commit message format

Controlled by `--commit-format`:

=== "default"

    ```
    robot-to 1: <result summary>
    ```

=== "conventional"

    ```
    feat(scope): <result summary>
    ```

    The `type` and `scope` come from the robot's submitted result (defaulting to
    `chore`). See [Commit conventions](../configuration/settings.md#commit_format).

## The run directory

All run state lives under `.robot_lab_to/runs/<run_id>/` (the directory is added
to `.git/info/exclude` automatically):

```
.robot_lab_to/
└── runs/
    └── 20260623-144554-3e5c27/
        ├── notes.md         # cross-iteration memory (human-readable)
        ├── run.log          # JSONL event log (machine-readable)
        └── checkpoints/     # pre-edit file snapshots (local_guards only)
```

- **`notes.md`** — written by the orchestrator after each iteration; read by the
  robot at the start of the next. See [Cross-Iteration Memory](../concepts/notes.md).
- **`run.log`** — one JSON object per line, one per lifecycle event. See
  [Run State & Event Log](../concepts/run-state.md).
- **`checkpoints/`** — first-write-wins file snapshots taken before a Write/Edit,
  created only when `--local-guards` is active. See [Guardrails](../local-models/guardrails.md).

## One iteration, step by step

```
iteration:start          → fresh robot built with prompt + notes
agent:run:start          → robot.run() begins
  (robot uses tools, calls submit_iteration_result)
agent:run:end
agent:nudge?             → if no result submitted, re-ask (max_submit_nudges)
verify:start / verify:*  → run --verify-command (if set)
commit:success           → git add -A && commit       (success path)
  — or —
iteration:failure        → git reset --hard            (failure path)
iteration:verify_failure → git reset --hard            (verify failed)
```

A successful iteration resets the consecutive-failure counter; a failure
increments it (and may trip `--max-consecutive-failures`).

## The exit summary

When the loop ends — whether it completed, hit a stop condition, or aborted —
`robot-to` prints a summary to stdout:

```
robot-to complete — claude-sonnet-4-6 — 4m 12s
Branch: robot-to/migrate-to-rspec-20260623-144554

  Iterations:   8   (6 committed, 2 rolled back)
  Changes:      +312 / -47 across 14 files
  Tokens:       1,204,883 in / 38,902 out

Run state:  .robot_lab_to/runs/20260623-144554-3e5c27/
Next steps:
  git log robot-to/migrate-to-rspec-20260623-144554
  git diff 362b8d9..HEAD
```

If the run was stopped early, the header shows the reason (e.g. `max iterations
reached (8)`, `4 consecutive failures`, or `stop condition met: ...`).

---

Next: the full lifecycle in [The Iteration Loop](../concepts/iteration-loop.md).
