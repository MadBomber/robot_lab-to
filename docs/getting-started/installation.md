# Installation

## Requirements

| Requirement | Notes |
|-------------|-------|
| Ruby **>= 3.2** | Set in the gemspec `required_ruby_version`. |
| Git | A repository with at least one commit. The loop creates a branch and commits there. |
| `robot_lab` | The core framework `robot_lab-to` builds on. |
| An LLM provider | A cloud API key, **or** a local [Ollama](https://ollama.com) server (see [Local Models](../local-models/index.md)). |

## Install the gem

```bash
gem install robot_lab-to
```

Or add it to a `Gemfile`:

```ruby
gem "robot_lab-to"
```

```bash
bundle install
```

This installs the `robot-to` executable on your `PATH`.

## Provider credentials

`robot_lab-to` passes your configured provider and model straight through to
RobotLab / RubyLLM. Provide credentials the usual way for your provider:

=== "Anthropic"

    ```bash
    export ANTHROPIC_API_KEY="sk-ant-..."
    robot-to "..." --provider anthropic --model claude-sonnet-4-6
    ```

=== "OpenAI"

    ```bash
    export OPENAI_API_KEY="sk-..."
    robot-to "..." --provider openai --model gpt-5.5
    ```

=== "Local (Ollama)"

    No API key required. See [Ollama Setup](../local-models/ollama.md) for the
    full configuration — local models need `--provider openai` against Ollama's
    OpenAI-compatible endpoint plus `--no-stream` and `--local-guards`.

The default provider/model is `openai` / `gpt-5.5` (see
[Settings Reference](../configuration/settings.md)).

## Verify the installation

```bash
robot-to --version
```

## Prepare your project

The loop branches from `HEAD` and commits each successful iteration, so the
working repository must have at least one commit:

```bash
git init
git add -A
git commit -m "initial"          # or: git commit --allow-empty -m "initial"
```

Run state is written under `.robot_lab_to/` and automatically added to
`.git/info/exclude`, so it never pollutes your working tree or commits.

You're ready — continue to the [Quick Start](quick-start.md).
