# CLI Reference

The `robot-to` executable runs an autonomous loop toward an objective.

## Synopsis

```
robot-to [objective] [options]
```

The **objective** is a single argument (quote it). If omitted, `robot-to` reads
the objective from standard input — handy for long objectives:

```bash
robot-to "Add request logging middleware and tests"

# or via stdin
echo "Add request logging middleware and tests" | robot-to
```

## Options

| Flag | Argument | Default | Description |
|------|----------|---------|-------------|
| `--provider` | `NAME` | `openai` | LLM provider (`anthropic`, `openai`, …). |
| `--model` | `MODEL` | `gpt-5.5` | Model identifier for the provider. |
| `--max-iterations` | `N` | *unlimited* | Stop after `N` iterations. |
| `--max-tokens` | `N` | *unlimited* | Stop after `N` total tokens. |
| `--stop-when` | `CONDITION` | *unset* | Natural-language stop condition the robot evaluates. |
| `--max-consecutive-failures` | `N` | `3` | Abort after `N` consecutive failures. |
| `--verify-command` | `CMD` | *unset* | Command that must pass before a success is committed. |
| `--verify-timeout` | `SECONDS` | `600` | Timeout for `--verify-command`. |
| `--max-verify-repairs` | `N` | `2` | Repair-in-place attempts when the eval's gate fails before rolling back. |
| `--eval` | `code`\|`null`\|`prose` | *code if verify/measure/target set, else null* | Eval strategy — see [Evals](../concepts/evals.md). |
| `--measure` | `CMD` | *unset* | Command printing a numeric score (higher = better); drives `Evals::Code`. |
| `--target` | `FLOAT` | *unset* | Stop once the measured score reaches this. |
| `--spec` | `PATH` | *unset* | Spec/outline artifact `Evals::Prose`'s judge measures against. |
| `--floor` | `CMD` | *unset* | Mechanizable floor check for prose (links, outline coverage, AI-tells). |
| `--judge-model` | `MODEL` | *`--model`* | Model for the pairwise prose judge. |
| `--stop-on-plateau` | `N` | *unset — off* | Stop after `N` iterations with no committed improvement. |
| `--[no-]require-improvement` | — | on | Roll back gate-passing iterations that don't beat the parent (default on). |
| `--protect-path` | `GLOB` (repeatable) | *none* | Lock a grader file from robot edits (always-on `GraderLock`). |
| `--commit-format` | `default`\|`conventional` | `default` | Commit message format. |
| `--run-dir` | `PATH` | `.robot_lab_to` | Directory for run state. |
| `--local-guards` | — | off | Add built-in file tools + small-model guardrails. |
| `--no-stream` | — | streaming on | Disable streaming (required for local Ollama tool calls). |
| `--debug` | — | off | Keep verbose provider logging enabled. |
| `--version` | — | — | Print version and exit. |
| `-h`, `--help` | — | — | Show help and exit. |

See the [Settings Reference](settings.md) for the full meaning of each option and
its config-file / environment-variable equivalents.

## Examples

A bounded run with a verification gate:

```bash
robot-to "Fix the failing parser tests" \
  --provider anthropic \
  --model claude-sonnet-4-6 \
  --max-iterations 15 \
  --verify-command "bundle exec rake test"
```

An overnight migration with a natural-language stop condition:

```bash
robot-to "Migrate from Minitest to RSpec" \
  --max-iterations 60 \
  --max-tokens 3000000 \
  --verify-command "bundle exec rake" \
  --stop-when "every test file is RSpec and the suite passes" \
  --commit-format conventional
```

A scored run that descends toward a measured target (see [Evals](../concepts/evals.md)):

```bash
robot-to "Raise parser coverage to 90%" \
  --verify  "bundle exec rake test" \
  --measure "bundle exec rake coverage" \
  --target  90 \
  --protect-path test/coverage_helper.rb
```

A judged prose run that ends on plateau instead of a target:

```bash
robot-to "Write an opinionated guide to the Viable Systems Model" \
  --eval prose --spec outline.md --floor "rake docs:lint" \
  --stop-on-plateau 3
```

A fully local run on Ollama (see [Local Models](../local-models/index.md)):

```bash
robot-to "Add a greet(name) method in greeter.rb" \
  --provider openai \
  --model gpt-oss:20b \
  --local-guards \
  --no-stream \
  --max-iterations 5
```

## Exit behavior

`robot-to` runs to completion or until a stop condition trips, then prints an
[exit summary](../getting-started/anatomy-of-a-run.md#the-exit-summary). Press
**Ctrl-C** for a graceful stop — the in-flight iteration is rolled back, the loop
exits, and the summary still prints.
