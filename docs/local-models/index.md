# Local Models

`robot_lab-to` can drive a **local** model — running entirely offline against an
[LM Studio](https://lmstudio.ai) server via the `:lms` provider — instead of a cloud API. This is the
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
lms server start
lms get qwen/qwen3.8-27b

# 2. Run robot-to against it
robot-to "Add a greet(name) method in greeter.rb" \
  --provider lms \
  --model qwen/qwen3.8-27b \
  --local-guards \
  --max-iterations 5
```

The full setup — including requiring the ruby_llm-providers-lms gem — is on
the [LM Studio Setup](lm-studio.md) page.

## Why these flags

Driving a local model end-to-end takes two settings. Each exists because of a
concrete limitation discovered in testing:

| Flag / setting | Why |
|----------------|-----|
| `--provider lms` | The ruby_llm-providers-lms gem's LM Studio provider — no API key, and local model ids are assumed to exist. Its default `:chat_completions` protocol supports client tools, structured output, and streaming. |
| `--local-guards` | Attaches the file tools the model needs to do work, plus guardrails that make those tools safe for a small model. |

See [LM Studio Setup](lm-studio.md) for the details.

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
| `qwen/qwen3.8-27b` | 27B | ✅ reliable | Honors `tool_choice` and structured output; the right pick for the autonomous loop. **Recommended.** |
| `openai/gpt-oss-20b` | 20B | ⚠️ partial | Accepts tool definitions but ignores `tool_choice: required`, and its structured output parses without meaning anything. Fine for simple chat, not for the loop. |

Prefer a larger, instruction-following model for the autonomous loop — it has to
both use tools *and* remember to submit its result every iteration.

---

- [LM Studio Setup](lm-studio.md) — install, serve, and configure.
- [Built-in Tools](tools.md) — what `read`/`write`/`edit`/`bash` do.
- [Guardrails](guardrails.md) — the small-model safety policies.
