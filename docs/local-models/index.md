# Local Models

`robot_lab-to` can drive a **local** model — running entirely offline against an
[Ollama](https://ollama.com) server — instead of a cloud API. This is the
"local assistant" mode: no API keys, no per-token cost, no data leaving your
machine.

Local models are smaller and less forgiving than frontier models, so this mode
adds two things:

- **Built-in file tools** (`read`, `write`, `edit`, `bash`) — a small, predictable
  tool surface the model can use to do real work.
- **Guardrails** — `RobotLab::Hook` policies that catch the mistakes small models
  reliably make, before they corrupt the working tree or burn the token budget.

Both are enabled together with `--local-guards`.

## The short version

```bash
# 1. Serve a tool-capable model
ollama pull gpt-oss:20b

# 2. Run robot-to against it
robot-to "Add a greet(name) method in greeter.rb" \
  --provider openai \
  --model gpt-oss:20b \
  --local-guards \
  --no-stream \
  --max-iterations 5
```

The full setup — including the RubyLLM configuration that points `:openai` at
Ollama — is on the [Ollama Setup](ollama.md) page.

## Why these flags

Driving a local model end-to-end requires three non-obvious settings. Each exists
because of a concrete limitation discovered in testing:

| Flag / setting | Why |
|----------------|-----|
| `--provider openai` (+ Ollama base URL) | RubyLLM's native `:ollama` provider doesn't reliably get these models to emit tool calls. Routing through the `:openai` provider against Ollama's OpenAI-compatible `/v1` endpoint does. |
| `--no-stream` | Ollama suppresses tool calls when the response is streamed. With streaming off, tool calls come through. |
| `--local-guards` | Attaches the file tools the model needs to do work, plus guardrails that make those tools safe for a small model. |

See [Ollama Setup → Streaming and tool calls](ollama.md#streaming-and-tool-calls)
for the details.

## The design philosophy

This mode is inspired by the research behind
[`little-coder`](https://github.com/itayinbarr/little-coder): the same small model
scored **2.4× higher** on a coding benchmark through a guard-rich harness than it
did unscaffolded. With small local models, **the harness is the product** — a
frontier model forgives a sloppy tool loop; a 9–35B local model does not.

The guardrails are policies that intercept the model's tool calls:

- **`write-guard`** — refuses `write` on a file that already exists (small models
  rewrite whole files and destroy content); redirects to `edit`.
- **`read-before-edit`** — refuses `edit` on a file the model hasn't read this run,
  so `oldText` reflects the real contents.
- **`checkpoint`** — snapshots a file before the first Write/Edit, for fine-grained
  recovery within an iteration.
- **`quality-monitor`** — detects a model spinning on the same tool call and stops
  it before it burns the token budget.

See [Guardrails](guardrails.md) for how each works.

## Choosing a model

The model **must support tool calling**. In testing on an M2 Max:

| Model | Size | Tool calls? | Notes |
|-------|------|-------------|-------|
| `gpt-oss:20b` | 20B | ✅ reliable | Called tools *and* `submit_iteration_result`; completed full runs cleanly. **Recommended.** |
| `qwen3` | 8B | ✅ tools work | Created files via the write tool, but didn't reliably call `submit_iteration_result` (the final-report step). |
| `phi4-mini` | 3.8B | ❌ | Explains instead of calling tools. |

Prefer a larger, instruction-following model for the autonomous loop — it has to
both use tools *and* remember to submit its result every iteration.

---

- [Ollama Setup](ollama.md) — install, serve, and configure.
- [Built-in Tools](tools.md) — what `read`/`write`/`edit`/`bash` do.
- [Guardrails](guardrails.md) — the small-model safety policies.
