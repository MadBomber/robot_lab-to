# Ollama Setup

This page covers running `robot_lab-to` against a local
[Ollama](https://ollama.com) server end-to-end.

## 1. Install and start Ollama

```bash
# macOS / Linux
curl -fsSL https://ollama.com/install.sh | sh

# Ollama runs a server on http://localhost:11434
```

## 2. Pull a tool-capable model

The model **must** support tool calling. `gpt-oss:20b` is the recommended choice
(see [model selection](index.md#choosing-a-model)):

```bash
ollama pull gpt-oss:20b
```

You can confirm a model advertises tool support:

```bash
curl -s http://localhost:11434/api/tags | jq '.models[] | {name, caps: .capabilities}'
```

## 3. Point RubyLLM at Ollama

`robot_lab-to` reaches the model through RobotLab / RubyLLM. The robust path is
the **`:openai` provider** aimed at Ollama's OpenAI-compatible `/v1` endpoint.
Configure RubyLLM once, before launching the run:

```ruby
require "ruby_llm"
require "robot_lab"
require "robot_lab/to"

RubyLLM.configure do |c|
  c.openai_api_base = "http://localhost:11434/v1"
  c.openai_api_key  = "ollama"   # ignored by Ollama, but RubyLLM requires a value
  c.request_timeout = 600
end

RobotLab::To.run(
  "Add a greet(name) method in greeter.rb",
  provider: :openai,
  model: "gpt-oss:20b",
  local_guards: true,
  stream: false,
  max_iterations: 5
)
```

!!! note "Why a wrapper script"
    The Ollama base-URL configuration lives in RubyLLM's global config, so it's
    set in a small Ruby launcher (as above) rather than via a `robot-to` CLI flag.
    The CLI flags `--provider openai --model gpt-oss:20b --local-guards --no-stream`
    cover the rest; only the base URL needs the wrapper. You can also set it in
    your application's RubyLLM initializer.

## 4. Run

From the launcher above, or — once the base URL is configured in your environment
— from the CLI:

```bash
robot-to "Add a greet(name) method in greeter.rb" \
  --provider openai \
  --model gpt-oss:20b \
  --local-guards \
  --no-stream \
  --max-iterations 5
```

## Streaming and tool calls

**Local Ollama models must run non-streaming** (`--no-stream` / `stream: false`).

Ollama's OpenAI-compatible endpoint suppresses tool calls when the response is
streamed — the model "thinks" but never emits a tool call, so the robot can't do
any work. With streaming disabled, tool calls come through normally.

The trade-off: streaming is what enables per-chunk token accounting and
mid-iteration token-budget enforcement. With `--no-stream`, tokens are accounted
from each iteration's *result* instead, and `--max-tokens` is enforced at
iteration boundaries rather than mid-stream. For overnight local runs this is
almost always fine.

## Why not the native `:ollama` provider?

RubyLLM ships a native `:ollama` provider, but in testing it did **not** reliably
get tool-capable models (e.g. qwen3) to emit tool calls — the same model tool-calls
correctly through the `:openai` provider against Ollama's `/v1` endpoint. Until
that changes, prefer `provider: :openai` + `openai_api_base` for `robot_lab-to`.

## Registering models (if needed)

RubyLLM validates models against its registry. `robot_lab-to` sets
`assume_model_exists` when a provider is given, which is enough for a bare chat —
but attaching tools triggers a capability lookup that can raise
`ModelNotFoundError` for an unregistered model. If you hit that, refresh the
registry so your local models are known:

```ruby
RubyLLM.models.refresh!   # discovers locally-served Ollama models
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Model thinks but never calls a tool | Streaming is on | Add `--no-stream`. |
| `RobotLab::ModelNotFoundError` when tools attach | Model not in RubyLLM registry | `RubyLLM.models.refresh!`. |
| Every iteration "did not submit" | Model too small to follow the final-report step | Use a larger model (e.g. `gpt-oss:20b`). |
| No tool calls at all, model only explains | Model lacks tool support | Pick a model whose `capabilities` include `tools`. |

---

Next: [Built-in Tools](tools.md).
