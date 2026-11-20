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
    chore: <result summary>
    ```

    The submitted result carries no `type` or `scope`, so the type is always
    `chore`. See [Commit conventions](../configuration/settings.md#commit_format).

## The run directory

All run state lives under `.robot_lab_to/runs/<run_id>/` (the directory is added
to `.git/info/exclude` automatically):

```
.robot_lab_to/
└── runs/
    └── 20260623-144554-3e5c27/
        ├── notes.md         # cross-iteration memory (human-readable)
        ├── run.log          # JSONL event log (machine-readable)
        ├── run.json         # serialized run state (enables --resume)
        ├── decisions/       # decision files (d-*.md) the robot raised
        └── checkpoints/     # pre-edit file snapshots (local_guards only)
```

- **`notes.md`** — written by the orchestrator after each iteration; read by the
  robot at the start of the next. See [Cross-Iteration Memory](../concepts/notes.md).
- **`run.log`** — one JSON object per line, one per lifecycle event. See
  [Run State & Event Log](../concepts/run-state.md).
- **`run.json`** — the run's counters, branch, and paths, rewritten after every
  iteration so `robot-to --resume <run_id>` can continue it.
- **`decisions/`** — one markdown file per decision the robot raised with
  `request_decision`; list them with `robot-to decisions`.
- **`checkpoints/`** — first-write-wins file snapshots taken before a Write/Edit,
  created only when `--local-guards` is active. See [Guardrails](../local-models/guardrails.md).

## One iteration, step by step

```
iteration:start           → fresh robot built with prompt + notes
agent:run:start           → robot.run() begins
  (robot uses tools, calls submit_iteration_result)
agent:run:end
agent:nudge?              → if no result submitted, re-ask (max_submit_nudges)
eval                      → the configured eval scores the working tree (if reported success)
commit:success            → git add -A && commit                 (gate ok + improved)
  — or —
iteration:no_improvement  → git reset --hard                     (gate ok, not improved)
iteration:gate_failure    → git reset --hard (after eval:repair)  (gate failed)
iteration:failure         → git reset --hard                     (robot reported failure / no submit)
```

A committed iteration resets the consecutive-failure counter and the plateau
counter; a failure or gate failure increments consecutive-failures, and any
non-committing outcome increments the plateau counter (may trip
`--max-consecutive-failures` or `--stop-on-plateau`). See
[Evals](../concepts/evals.md) for the full scoring model — by default (no
`--verify-command`/`--eval`), every reported success commits, matching this
page's simpler mental model.

## The exit summary

When the loop ends — whether it completed, hit a stop condition, or aborted —
`robot-to` prints a summary to stdout:

```
robot-to complete — claude-sonnet-4-6 — 4m 12s
Branch: robot-to/migrate-to-rspec-20260623-144554

Iterations:      8 total  (6 good / 2 failed)
Tokens:          1,243,785  (1,204,883 in / 38,902 out)
Commits:         6
Changes:         +312 / -47 lines across 14 files

Notes:   .robot_lab_to/runs/20260623-144554-3e5c27/notes.md
Log:     .robot_lab_to/runs/20260623-144554-3e5c27/run.log

Next steps:
  git log --oneline <base_commit>..HEAD
  git diff --stat <base_commit>..HEAD
  gh pr create
```

`<base_commit>` is printed as the full SHA; the "Next steps" block appears only
when at least one commit was made. If the run was stopped early, the header reads
`robot-to stopped — <model> — <elapsed>` and the `Branch:` line is replaced by a
`Reason:` line (e.g. `max iterations reached (8)`, `4 consecutive failures`, or
`stop condition met: ...`).

---

Next: the full lifecycle in [The Iteration Loop](../concepts/iteration-loop.md).
