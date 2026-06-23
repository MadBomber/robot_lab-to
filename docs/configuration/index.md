# Configuration

`robot_lab-to` is configured through a layered cascade built on
[`myway_config`](https://github.com/MadBomber/myway_config). Lower layers provide
defaults; higher layers override them.

## The cascade

From lowest to highest precedence:

```
1. Bundled defaults        lib/robot_lab/to/config/defaults.yml
2. User config file        ~/.config/robot_lab/to.yml
3. Environment variables   ROBOT_LAB_TO_*
4. CLI flags / To.run args  (highest — always wins)
```

A value set at a higher layer overrides the same value from any lower layer.

## 1. Bundled defaults

Shipped with the gem. You never edit these, but they define the baseline:

```yaml
defaults:
  provider: openai
  model: gpt-5.5
  max_tool_rounds: 100
  max_consecutive_failures: 3
  max_retries: 2
  max_submit_nudges: 1
  verify_timeout: 600
  commit_format: default
  run_dir: .robot_lab_to
  local_guards: false
  stream: true
  debug: false
```

## 2. User config file

Create `~/.config/robot_lab/to.yml` to set your own defaults — for example, to
always use a local model:

```yaml
provider: openai          # routes to Ollama's OpenAI-compatible endpoint
model: gpt-oss:20b
local_guards: true
stream: false
max_consecutive_failures: 4
```

These apply to every `robot-to` run unless overridden by an env var or CLI flag.

## 3. Environment variables

Every setting can be set via an environment variable prefixed with
`ROBOT_LAB_TO_`. Nested keys use a double underscore (rare here, since the config
is flat):

```bash
export ROBOT_LAB_TO_MODEL="gpt-oss:20b"
export ROBOT_LAB_TO_LOCAL_GUARDS=true
export ROBOT_LAB_TO_MAX_CONSECUTIVE_FAILURES=4
```

Provider **API keys** are *not* `robot_lab-to` settings — they are read by the
underlying provider (e.g. `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`).

## 4. CLI flags / `To.run` arguments

The highest-precedence layer. Anything passed on the command line (or as a keyword
to `RobotLab::To.run`) wins over all other layers:

```bash
robot-to "..." --model claude-sonnet-4-6 --max-iterations 20
```

```ruby
RobotLab::To.run("...", model: "claude-sonnet-4-6", max_iterations: 20)
```

Some options are **CLI-only** (no YAML default) because they are run-specific:
`--max-iterations`, `--max-tokens`, `--stop-when`, and `--verify-command`. When
unset they mean "no limit / not configured".

---

- See the [Settings Reference](settings.md) for every option in detail.
- See the [CLI Reference](cli.md) for every flag.
