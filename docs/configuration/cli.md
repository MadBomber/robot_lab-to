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
