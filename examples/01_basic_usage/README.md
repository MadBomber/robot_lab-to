# 01 — Basic Usage

An end-to-end use of `robot_lab-to`, driven programmatically with
`RobotLab::To.run`.

The script ([`basic_usage.rb`](basic_usage.rb)):

1. Creates a fresh **`project/`** git repository next to the script,
   seeded with a **failing Minitest suite** for a Roman-numeral library
   (`test/roman_numeral_test.rb`). It's git-ignored and re-created on each run.
2. Runs an autonomous loop with the objective *"implement `lib/roman_numeral.rb`
   until the seeded test suite passes."* Because the tests are fixed and the robot
   may not edit them, it has to satisfy real, externally-defined requirements it
   can't game.
3. Gates each iteration on `ruby -Ilib -Itest test/roman_numeral_test.rb` — a
   change is committed only when the suite is green; otherwise it's rolled back.
4. Stops early (via `stop_when`) once the suite passes, and prints the resulting
   branch, commit history, the generated implementation, and a final test run.

It exercises the full loop over several iterations: **branch → iterate → verify →
commit on green / roll back on red**.

### The seeded spec

The library must provide `RomanNumeral.to_roman(int)` and
`RomanNumeral.from_roman(str)` with: subtractive notation (`IV`, `IX`, `XL`, …),
the `1..3999` range, round-trip correctness, case-insensitive parsing, and
`ArgumentError` on invalid input — including **non-canonical** numerals like
`"IIII"`. The full expectations live in the seeded `test/roman_numeral_test.rb`.

## Prerequisites

Either a **local Ollama** server (default, no API key) or a **cloud** provider key.

=== "Local Ollama (default)"

    ```bash
    ollama serve &                # if not already running
    ollama pull qwen3.6:latest    # a tool-capable model
    ```

=== "Cloud provider"

    ```bash
    export ANTHROPIC_API_KEY="sk-ant-..."   # or OPENAI_API_KEY
    ```

## Run it

From the gem root:

```bash
# Local Ollama (default)
bundle exec ruby examples/01_basic_usage/basic_usage.rb

# A cloud model instead
RLTO_LOCAL=false RLTO_PROVIDER=anthropic RLTO_MODEL=claude-sonnet-4-6 \
  bundle exec ruby examples/01_basic_usage/basic_usage.rb
```

## Configuration

All optional, set via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `RLTO_LOCAL` | `true` | Use a local Ollama model. Set `false` for a cloud provider. |
| `RLTO_PROVIDER` | `openai` (local) | LLM provider passed to `RobotLab::To.run`. |
| `RLTO_MODEL` | `qwen3.6:latest` (local) | Model id. Any tool-capable model works. |
| `OLLAMA_BASE` | `http://localhost:11434/v1` | Ollama's OpenAI-compatible endpoint. |

## What you'll see

A `RobotLab::Hook` (`FeedbackHook` in the script) narrates the robot's actions
live, so the run never sits silent while the model works:

```
Cleaning leftover: .../examples/01_basic_usage/project
Project dir:     examples/01_basic_usage/project
Provider/model:  openai/qwen3.6:latest (local Ollama)
Objective:       implement lib/roman_numeral.rb to pass the test suite

      🤔 thinking…
      📖 read test/roman_numeral_test.rb
      📝 write lib/roman_numeral.rb
      💻 bash: ruby -Ilib -Itest test/roman_numeral_test.rb
         ↳ exit 1
      ✏️ edit lib/roman_numeral.rb
      💻 bash: ruby -Ilib -Itest test/roman_numeral_test.rb
         ↳ exit 0
      ✅ submit result: Implemented RomanNumeral.to_roman/from_roman; all 9 tests pass.

=== Result ===
Branch:  robot-to/implement-a-roman-numeral-library-...

Commits:
4a59bbc robot-to 1: Implemented lib/roman_numeral.rb ... all 9 tests pass.
72b06ec initial: failing roman-numeral test suite

lib/roman_numeral.rb:
module RomanNumeral
  ...
end

Final test run:
9 runs, 594 assertions, 0 failures, 0 errors, 0 skips

Notes:    examples/01_basic_usage/.robot_lab_to/runs/.../notes.md
Project:  examples/01_basic_usage/project
Run logs: examples/01_basic_usage/.robot_lab_to
```

### Live feedback via the hook system

`FeedbackHook < RobotLab::Hook` is registered globally with `RobotLab.on(...)`,
so it applies to every per-iteration robot the orchestrator builds — no change to
the orchestrator needed. It implements three hook methods:

| Hook method | Reports |
|-------------|---------|
| `before_llm_generation` | `🤔 thinking…` — the model started generating |
| `before_tool_call` | the action: read / write / edit / bash / submit |
| `after_tool_call` | a shell exit code, or a tool error |

This is a compact, practical example of the robot_lab hook system; the guardrails
shipped with `--local-guards` use the same mechanism.

> **Note:** robot_lab-to's own `robot-to: …` progress lines use `Kernel#warn`,
> which is silenced when Ruby warnings are disabled (`$VERBOSE` is `nil`, common
> under `bundle exec`). The hook writes to `$stderr` directly, so its narration
> always shows.

Everything the example produces stays under `examples/01_basic_usage/`:

```
examples/01_basic_usage/
├── basic_usage.rb
├── project/     # the throwaway git repo (re-created on every run)
└── .robot_lab_to/       # run event logs + cross-iteration notes.md
```

Each run **starts with a clean slate** — `project/` and `.robot_lab_to/`
left over from a previous execution are deleted before setup, then rebuilt. The
most recent run's repo, logs, and `notes.md` remain afterward for inspection
(until the next run clears them). Both are git-ignored, so you never need to
clean them up by hand.

## How it maps to the library

The whole example is one call:

```ruby
RobotLab::To.run(
  objective,
  provider:       :openai,    # routes to Ollama for local runs
  model:          "qwen3.6:latest",
  local_guards:   true,       # built-in file tools + guardrails
  stream:         false,      # Ollama tool calls need non-streaming
  max_iterations: 6,
  verify_command: "ruby -Ilib -Itest test/roman_numeral_test.rb",
  stop_when:      "test/roman_numeral_test.rb passes with 0 failures and 0 errors"
)
```

For the meaning of each option, see the
[Settings Reference](https://madbomber.github.io/robot_lab-to/configuration/settings/)
and, for the local-model specifics, the
[Local Models guide](https://madbomber.github.io/robot_lab-to/local-models/).
