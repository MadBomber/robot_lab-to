# Settings Reference

Every `robot_lab-to` setting, its default, and what it controls. Each setting can
be supplied via the user config file, an `ROBOT_LAB_TO_*` environment variable, a
CLI flag, or a `RobotLab::To.run` keyword argument (see
[the cascade](index.md#the-cascade)).

## Model & provider

### `provider`

- **Default:** `openai`
- **CLI:** `--provider NAME`

The LLM provider, passed through to RobotLab / RubyLLM. Use `anthropic`,
`openai`, etc. For **local Ollama models**, set this to `openai` and point
RubyLLM at Ollama's OpenAI-compatible endpoint — see [Ollama Setup](../local-models/ollama.md).

### `model`

- **Default:** `gpt-5.5`
- **CLI:** `--model MODEL`

The model identifier for the chosen provider (e.g. `claude-sonnet-4-6`,
`gpt-5.5`, `gpt-oss:20b`).

### `stream`

- **Default:** `true`
- **CLI:** `--no-stream` to disable

Whether to stream the model response. Streaming enables per-chunk token
accounting and mid-iteration token-budget enforcement. **Local Ollama models must
run with `--no-stream`** — Ollama suppresses tool calls when streaming. With
streaming off, tokens are accounted from each iteration's result instead. See
[Streaming and tool calls](../local-models/ollama.md#streaming-and-tool-calls).

## Loop control

### `max_iterations`

- **Default:** *(unset — no limit)*
- **CLI:** `--max-iterations N`

Stop after `N` iterations. CLI-only; strongly recommended for unattended runs.

### `max_tokens`

- **Default:** *(unset — no limit)*
- **CLI:** `--max-tokens N`

Stop once cumulative input+output tokens reach `N`. CLI-only.

### `max_consecutive_failures`

- **Default:** `3`
- **CLI:** `--max-consecutive-failures N`

Abort after `N` consecutive failed iterations. Resets to zero on each successful,
committed iteration. The primary safety net against a run going nowhere.

### `stop_when`

- **Default:** *(unset)*
- **CLI:** `--stop-when "<condition>"`

A natural-language condition the robot evaluates after each successful iteration.
When the robot judges it met, the run stops. CLI-only. See
[Stop Conditions](../concepts/stop-conditions.md).

### `max_submit_nudges`

- **Default:** `1`

How many times to re-prompt a robot that finished without calling
`submit_iteration_result`. Recovers the "thinks but doesn't act" case before
counting the iteration as a failure.

### `max_retries`

- **Default:** `2`

How many consecutive *errors* (exceptions, e.g. transient API failures) to retry
before aborting. Retries use an interruptible exponential backoff
(`60 × 2ⁿ` seconds).

### `max_tool_rounds`

- **Default:** `100`

Passed to the robot — the maximum number of tool-call rounds within a single
iteration before RobotLab's circuit breaker stops it.

## Verification

### `verify_command`

- **Default:** *(unset — no verification)*
- **CLI:** `--verify-command "CMD"`

A command that must exit `0` before a robot's claimed success is committed.
CLI-only. See [Verification Gate](../concepts/verification.md).

### `verify_timeout`

- **Default:** `600` (seconds)
- **CLI:** `--verify-timeout SECONDS`

Maximum time `verify_command` may run before it is killed (whole process group)
and the gate fails.

## Local models

### `local_guards`

- **Default:** `false`
- **CLI:** `--local-guards`

Attach the built-in file tools (`read`, `write`, `edit`, `bash`) and the
small-model guardrail hooks. Designed for local models that need a more
constrained, forgiving tool surface. See [Local Models](../local-models/index.md).

## Git & output

### `commit_format`

- **Default:** `default`
- **CLI:** `--commit-format default|conventional`

How commit messages are formatted:

=== "default"

    `robot-to <iteration>: <summary>`

=== "conventional"

    `<type>(<scope>): <summary>` — `type`/`scope` come from the robot's result
    (defaulting to `chore`). Follows [Conventional Commits](https://www.conventionalcommits.org/).

### `run_dir`

- **Default:** `.robot_lab_to`
- **CLI:** `--run-dir PATH`

Where run state (`runs/<run_id>/`) is written. Added to `.git/info/exclude`
automatically.

### `debug`

- **Default:** `false`
- **CLI:** `--debug`

Keep verbose RubyLLM/RobotLab provider logging enabled. The JSONL event log is
written regardless.

---

See the [CLI Reference](cli.md) for the command-line form of every option.
