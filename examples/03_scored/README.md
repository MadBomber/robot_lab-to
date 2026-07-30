# 03 — Scored runs (evals)

The `01_basic_usage` and `02_advanced_usage` examples use a **verify command**: a
change is committed if the test suite exits 0. That answers *"did it break?"* but
not *"is it better?"* — and an agent will happily report success on a change that
made no real progress.

An **eval** replaces the robot's self-report with an orchestrator-owned,
measurable judgement, and makes the loop **descend toward a target**. This example
is a cookbook of the three ways to score a run; each recipe is a drop-in change to
the `RobotLab::To.run` call (or the `robot-to` CLI) in the earlier examples.

---

## 1. Code — measured descent

For software, "better" is a number. Add a **measure** command (prints a number,
higher = better) and a **target**:

```bash
robot-to "Raise parser test coverage to 90%" \
  --verify  "bundle exec rake test" \      # floor: must stay green (correctness)
  --measure "bundle exec rake coverage" \  # descent signal (higher = better)
  --target  90                             # stop once the score reaches this
```

```ruby
RobotLab::To.run(
  "Raise parser test coverage to 90%",
  verify_command: "bundle exec rake test",
  eval_measure:   "bundle exec rake coverage",  # must print a number to stdout
  eval_target:    90.0,
  max_iterations: 20
)
```

An iteration commits only if it **improves** the measured score *and* the verify
floor passes; a change that scores no better is rolled back, so the branch
descends monotonically and the run stops itself at the target. Each iteration's
prompt now includes a **Score Feedback** section — "Best score committed so far:
84.0 (target: 90.0)" and a plateau warning — so the robot's next attempt is a
hypothesis against the target, not a blind guess.

> The `measure` command just has to print a number. `rake coverage`, a benchmark
> harness, `ruby -e 'puts passing_count'`, `grep -c` of a lint report — anything.

---

## 2. Prose — pairwise judgement

For a document or opinion piece there is no `rake coverage`. The **prose** eval
scores each draft with an LLM judge, comparing it *pairwise* against the last
committed version (absolute LLM scores drift; "is B better than A?" is reliable):

```bash
robot-to "Write an opinionated guide to the Viable Systems Model" \
  --eval  prose \
  --spec  outline.md \          # the spec the judge measures against
  --floor "rake docs:lint" \    # optional mechanizable checks (links, TODOs)
  --stop-on-plateau 3           # stop after 3 drafts with no improvement
```

A draft commits only when the judge rules it **better** than its parent. There's
no absolute target, so the run ends on `--stop-on-plateau` or when you stop it.
The judge reuses the doer's model unless you pass `--judge-model`.

The `outline.md` spec is **locked** for the whole run — the robot cannot edit the
criteria it is scored against. Add `--protect-path` for any other grader files.

---

## 3. Custom eval — your own scoring

Anything responding to `#score(context)` and returning an `Evals::Score` is an
eval. Pass an instance (or a proc) as `eval:`:

```ruby
class FixmeEval < RobotLab::To::Evals::Base
  # Fewer FIXMEs is better; done at zero.
  def score(context)
    remaining = Dir.glob(File.join(context.work_dir, "**/*.rb"))
                   .sum { |f| File.read(f).scan(/FIXME/).size }
    RobotLab::To::Evals::Score.new(
      gate_ok:    true,
      improved:   context.previous_value.nil? || remaining < context.previous_value,
      met_target: remaining.zero?,
      value:      -remaining,               # higher = better, so negate
      detail:     "#{remaining} FIXMEs left",
      output:     nil
    )
  end
end

RobotLab::To.run("Burn down the FIXMEs in lib/", eval: FixmeEval.new, max_iterations: 15)
```

The `context` gives you `work_dir`, `previous_ref` (the parent commit), and
`previous_value` (the last committed score) so you can compute `improved`
yourself. For CLI use, register it and pass `--eval fixme`:

```ruby
RobotLab::To.register_eval(:fixme) { |_config| FixmeEval.new }
```

---

## How the pieces fit

| Field on `Score` | Decides |
|------------------|---------|
| `gate_ok`        | correctness floor — must hold to commit at all |
| `improved`       | did it beat the parent? — the descent signal (commit vs. roll back) |
| `met_target`     | is the objective reached? — ends the run (orchestrator-owned) |
| `value`          | the score, for the trajectory / prompt feedback (nil for pairwise) |

The harness (loop, commit/rollback, stop conditions, grader lockdown, prompt
feedback) never changes per product — you only swap the eval.
