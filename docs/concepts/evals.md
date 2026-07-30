# Evals: Scoring Iterations

A robot reporting `success: true` is a claim; a `--verify-command` that must exit
`0` answers "did it break?". Neither answers the harder question: **is this
iteration actually better than the last one?** An agent will happily report
success — and pass a verify command — on a change that made no real progress.

An **eval** replaces the robot's self-report as the deciding authority. It is an
orchestrator-owned, pluggable scorer that judges the *uncommitted working tree*
after every iteration and returns a `Score`. The eval decides commit vs. rollback
(via `gate_ok` / `improved`) and, for measurable objectives, decides when the run
is *done* (`met_target`) — instead of the robot's self-reported
`should_fully_stop`.

This generalizes the [Verification Gate](verification.md): `--verify-command`
still exists and still works exactly as before, but it is now one input to the
default eval (`Evals::Code`) rather than the whole story.

## The `Score`

Every eval returns a `RobotLab::To::Evals::Score` — a `Data.define` with six
fields:

| Field | Meaning |
|-------|---------|
| `gate_ok` | The floor holds (correctness). Must be `true` to commit at all. |
| `improved` | Better than the parent commit? The descent signal. |
| `met_target` | The objective is measurably reached — an orchestrator-owned stop. |
| `value` | The score itself (higher = better); `nil` for pure-pairwise evals. |
| `detail` | One-line human summary, written to `notes.md` and the log. |
| `output` | Diagnostic text (gate output, judge rationale) fed to repair prompts; `nil` when there is none. |

`gate_ok?`, `improved?`, and `met_target?` predicate readers are also defined.

## How it drives the loop

```
robot says success ──► Eval#score ──► gate_ok? ──► improved (or --no-require-improvement)? ──► COMMIT
                                          │                        │
                                          │ no                     │ no
                                          ▼                        ▼
                              repair_until_gate (R2)         ROLLBACK  ([NO IMPROVEMENT])
                              then ROLLBACK if still failing
```

- **Gate fails** (`gate_ok: false`) — the failure output is handed back to the
  *same* robot up to `--max-verify-repairs` times, re-scoring after each attempt
  (this is the same R2 repair loop the verify gate always had — see
  [Verification Gate](verification.md)). If the budget runs out, the tree is
  rolled back and the notes get a `[VERIFY FAILED]` entry.
- **Gate passes but didn't improve** (`improved: false`) — rolled back with a
  `[NO IMPROVEMENT]` entry in `notes.md`, *unless* `--no-require-improvement` is
  passed (see [`require_improvement`](#require_improvement-strict-descent)
  below). This is **not** counted as a failure — it does not trip
  `--max-consecutive-failures` — but it does count toward
  [`--stop-on-plateau`](stop-conditions.md#plateau-no-improvement).
- **Gate passes and improved** — committed. `@run.last_score_value` is updated,
  the plateau counter resets, and `met_target?` is checked: if true, the run
  aborts with `target met: <detail>` — this **supersedes** the robot's
  self-reported `should_fully_stop`; `--stop-when` remains as a fallback.

Each iteration's verdict is logged as an `eval` event in `run.log` (`gate`,
`improved`, `value`, `met_target`, `detail`) — see
[Run State & Event Log](run-state.md).

## `Evals::Null` — the default, unscored

When nothing is configured, `Evals::Null` reports `gate_ok: true, improved: true,
met_target: false` on every call — every reported success commits, and the run
stops only via `--stop-when` or the other stop conditions. This is exactly
`robot_lab-to`'s original behavior; adding an eval is entirely opt-in.

## `Evals::Code` — measured descent

For software, "better" is measurable. `Evals::Code` composes two independent
commands:

| Option | Role |
|--------|------|
| `--verify-command CMD` | **Floor** — must exit `0` (correctness). Same gate as before. |
| `--measure CMD` | **Descent signal** — a command that prints a number to stdout; higher is better. |
| `--target FLOAT` | Stop once the measured value reaches this. |

```bash
robot-to "Raise parser coverage to 90%" \
  --verify  "bundle exec rake test" \      # floor: must stay green
  --measure "bundle exec rake coverage" \  # descent signal
  --target  90                             # stop once the score reaches this
```

`Evals::Code#score`:

- `gate_ok` — `true` when `--verify-command` is unset, or the command exits `0`.
- `value` — the **first number** matched in the `--measure` command's stdout
  (`/-?\d+(?:\.\d+)?/`), or `nil` if `--measure` is unset.
- `improved` — with no `value`, equals `gate_ok` (any gate-passing change is
  progress, matching legacy behavior). With a `value`, `true` only if it strictly
  beats `previous_value` (or there is no prior committed value yet).
- `met_target` — `true` once `value >= --target`.

**Backward compatible by construction:** with no `--measure`, `Evals::Code`
behaves exactly like the original verify-only gate — `improved == gate_ok`,
`met_target` never fires, and the run stops via `--stop-when` / the other stop
conditions as before.

The `--measure` command just has to print a number: `rake coverage`, a benchmark
harness, `ruby -e 'puts passing_count'`, `grep -c` of a lint report — anything.

## `Evals::Prose` — pairwise judgement

For a document, an opinion piece, or a book there is no `rake coverage`. Absolute
scores from an LLM are too noisy to descend against — but "is B better than A?"
is a reliable judgement. `Evals::Prose` asks a **judge model** to compare the
working tree to the last *committed* version:

```bash
robot-to "Write an opinionated guide to the Viable Systems Model" \
  --eval  prose \
  --spec  outline.md \          # the spec the judge measures against
  --floor "rake docs:lint" \    # optional mechanizable checks (links, TODOs)
  --judge-model claude-opus-4 \ # defaults to the doer's --model
  --stop-on-plateau 3           # stop after 3 drafts with no improvement
```

`Evals::Prose#score`:

- `gate_ok` — `true` when `--floor` is unset, or the floor command exits `0`. If
  the floor fails, the judge is **not** called (saves a request) and the verdict
  is forced to `:worse`.
- The judge is shown `VERSION A` (the parent commit) and `VERSION B` (the working
  tree) for every file that changed, plus the objective and — if `--spec` is set —
  its contents, and replies exactly one word: `better`, `worse`, or `same`.
  Anything ambiguous is treated as `:same` (does not count as improvement).
- **Brand-new document shortcut:** if the parent version is empty and the draft
  is not, the judge is skipped and the verdict is `:better` automatically — an
  "empty vs. content" pairwise comparison is degenerate and models frequently
  (and wrongly) call it `:same`.
- `improved` — `true` only when the verdict is `:better`.
- `met_target` — **always `false`.** There is no absolute milestone for prose;
  runs end via `--stop-on-plateau`, `--max-iterations`, or a human stopping it.
- `value` — always `nil` (pairwise verdicts have no scalar).

By default the judge **reuses the doer's `--model`** — no separate judge model is
required to get pairwise scoring. Pass `--judge-model` to use a different (often
cheaper, or deliberately more skeptical) model for the judge role. See
`examples/04_prose` in the gem for a worked two-model (doer + judge) setup.

## `require_improvement` — strict descent

- **Default: `true`.** A gate-passing iteration that does not beat the parent is
  rolled back (`[NO IMPROVEMENT]`), so the branch descends monotonically.
- `--no-require-improvement` restores "commit any gate-passing success," useful
  when you want every non-regressing attempt kept rather than only strict
  improvements.
- This is a hardcoded Ruby/CLI-only default (`Config#require_improvement?`), not
  in `defaults.yml` — set it per-run via `--no-require-improvement` or
  `RobotLab::To.run(require_improvement: false)`.

## Plateau: the primary stop for judged evals

`Evals::Prose` never sets `met_target`, so its natural terminator is
`--stop-on-plateau N` — stop after `N` iterations with no committed improvement.
Plateau is tracked independently of `--max-consecutive-failures` (which is for
the robot being genuinely broken — errors, gate failures, no submit); a
gate-passing "same" verdict is normal, healthy exploration for prose, not a
failure. See [Stop Conditions](stop-conditions.md#plateau-no-improvement).

## Score feedback in the prompt

When a run is scored (`--measure`, `--target`, `--eval prose`, or `--spec` is
set), `PromptBuilder` adds a **Score Feedback** section to every iteration's
system prompt:

- The best committed score so far and the target, if any: *"Best score committed
  so far: 84.0 (target: 90.0)."*
- A plateau warning after a run of non-improving iterations: *"The last 3
  iteration(s) did not improve and were rolled back... try a DIFFERENT approach
  now."*
- Otherwise, positive reinforcement: *"Your last change improved the result and
  was committed. Build on it."*

This turns each attempt into a testable hypothesis against the target rather
than a blind guess. Unscored runs (the `Evals::Null` default) get no such
section — behavior is unchanged.

## Guarding the grader (`GraderLock`)

Whatever the eval, the robot must not be able to "win" by editing the criteria
it is scored against. `Guards::GraderLock` — a `RobotLab::Hook` — refuses any
`write`/`edit` targeting a locked path, and refuses any `bash` command whose
string references one (matched conservatively, by absolute path or basename).

Locked paths come from two sources, merged:

- `Evals::Base#protected_paths` — `Evals::Prose#protected_paths` returns
  `[spec]` (a floor *command* isn't reliably a single file, so lock it
  separately with `--protect-path` if it's a script); `Evals::Code` locks
  nothing by default — **the test suite is deliberately editable**, since
  adding tests is how coverage legitimately rises.
- `--protect-path GLOB` (repeatable) — user-specified grader files for any eval,
  code or custom (e.g. a floor script, a scoring rubric).

`GraderLock` is installed in `Orchestrator#build_robot` whenever any protected
paths resolve, **independent of `--local-guards`** — unlike the small-model
guardrails (see [Guardrails](../local-models/guardrails.md)), a frontier model
can reward-hack too, so this one is always on.

```bash
robot-to "..." --eval code --measure "ruby score.rb" --target 100 \
  --protect-path score.rb --protect-path test/scoring_test.rb
```

## Custom evals

Three escape hatches, all via the Ruby API (`RobotLab::To.run` / `Config.new`):

```ruby
# (a) subclass RobotLab::To::Evals::Base
class BenchmarkEval < RobotLab::To::Evals::Base
  def score(ctx) = RobotLab::To::Evals::Score.new(gate_ok: true, improved: ..., met_target: ..., value: ..., detail: ..., output: nil)
end
RobotLab::To.run(objective, eval: BenchmarkEval.new)

# (b) a bare proc — wrapped in Evals::ProcEval automatically
RobotLab::To.run(objective, eval: ->(ctx) { RobotLab::To::Evals::Score.new(...) })

# (c) a registered symbol
RobotLab::To.register_eval(:benchmark) { |config| BenchmarkEval.new(target: config.eval_target) }
RobotLab::To.run(objective, eval: :benchmark)
```

!!! warning "`--eval` on the CLI only resolves `code` / `null` / `prose`"
    The CLI's `--eval NAME` flag always produces a **String**. The factory's
    registry lookup only matches a **Symbol** (`Config.new(eval: :benchmark)`),
    so a registered custom eval is reachable from the Ruby API but not yet from
    `--eval benchmark` on the command line — passing an unrecognized string
    raises `unknown eval strategy`. Likewise, pointing `--eval` at a `.rb` file
    path is not implemented; use the Ruby API's instance/proc/registered-symbol
    forms instead.

## Backward compatibility

| Invocation | Eval selected | Behavior |
|---|---|---|
| No `--verify-command`, no `--eval`, no `--measure`/`--target` | `Evals::Null` | Commit any reported success; stop via `--stop-when`. **Identical to pre-Evals behavior.** |
| `--verify-command "rake test"` only | `Evals::Code` (gate-only) | Commit on pass; stop via `--stop-when`. **Identical.** |
| Old `run.json` (`--resume`) | — | Loads; `last_score_value` / `iterations_since_improvement` default to `nil` / `0`. |

New behavior only activates when `--measure`, `--target`, `--eval prose`, or
`--stop-on-plateau` is supplied.

---

Next: [Run State & Event Log](run-state.md).
