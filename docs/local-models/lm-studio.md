# LM Studio Setup

This page covers running `robot_lab-to` against a local
[LM Studio](https://lmstudio.ai) server end-to-end, through the
[ruby_llm-providers-lms](https://github.com/madbomber/ruby_llm-providers-lms)
gem, which registers the `:lms` provider with RubyLLM.

## 1. Install and start LM Studio

Install LM Studio, then bootstrap its CLI and start the server:

```bash
lms bootstrap        # puts the `lms` CLI on your PATH
lms server start     # serves on http://localhost:1234
```

## 2. Download a tool-capable model

The model **must** support tool calling *and honor it*. `qwen/qwen3.8-27b` is
the recommended choice — it obeys `tool_choice` and returns meaningful
structured output, where `gpt-oss` models accept the request shape but ignore
it (see [model selection](index.md#choosing-a-model)):

```bash
lms get qwen/qwen3.8-27b
```

## 3. Point RubyLLM at LM Studio

`robot_lab-to` reaches the model through RobotLab / RubyLLM. Require the
provider gem and, only if your server is not on the default endpoint,
configure the base URL:

```ruby
require "ruby_llm"
require "ruby_llm/providers/lms"
require "robot_lab"
require "robot_lab/to"

RubyLLM.configure do |c|
  c.lms_api_base    = "http://localhost:1234/v1"  # the default; override if needed
  c.request_timeout = 600
end

RobotLab::To.run(
  "Add a greet(name) method in greeter.rb",
  provider: :lms,
  model: "qwen/qwen3.8-27b",
  local_guards: true,
  max_iterations: 5
)
```

No API key is needed — LM Studio's local server does not require one.

## 4. Run

From the launcher above, or from the CLI:

```bash
robot-to "Add a greet(name) method in greeter.rb" \
  --provider lms \
  --model qwen/qwen3.8-27b \
  --local-guards \
  --max-iterations 5
```

Because LM Studio is a local provider, RubyLLM assumes any model id you pass
exists — LM Studio just-in-time loads the model if it isn't loaded yet. No
registry refresh is needed.

## Protocols

LM Studio serves several API protocols on one port; the `:lms` provider
defaults to `:chat_completions`, which is the most capable one here — client
tools, structured output, streaming, and reasoning control all work. Stay on
the default for `robot_lab-to`. See the
[ruby_llm-providers-lms README](https://github.com/madbomber/ruby_llm-providers-lms)
for the full protocol matrix.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Connection error naming `lms server start` | Server not running | `lms server start`. |
| Tool calls accepted but ignored, or `{"name":"analysis","age":0}`-style junk from schemas | Model doesn't honor `tool_choice` / grammar output (e.g. `gpt-oss`) | Use `qwen/qwen3.8-27b`. |
| Every iteration "did not submit" | Model too small to follow the final-report step | Use a larger model (e.g. `qwen/qwen3.8-27b`). |
| No tool calls at all, model only explains | Model lacks tool support | Pick a tool-capable model. |

---

Next: [Built-in Tools](tools.md).
