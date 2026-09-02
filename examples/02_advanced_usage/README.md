# 02 — Advanced Usage

A multi-phase workflow that composes the two robot_lab subsystems: a **network of
robots** collaborates with you to ideate and plan, then **robot_lab-to**
autonomously implements the plan behind a real **quality gate**.

```
┌─ Phase 1: IDEATE ─┐   ┌─ Phase 2: PLAN ──┐      ┌─ Phase 3: IMPLEMENT ─────────┐
│  Ideator robot    │   │  Planner robot   │      │  robot_lab-to autonomous loop │
│  interviews you   │──▶│  writes the      │──▶──▶│  writes lib/ until the suite  │
│  (AskUser tool)   │   │  acceptance      │ spec │  passes AND the quality gate  │
│                   │   │  test suite      │      │  is clean                     │
└───────────────────┘   └──────────────────┘      └───────────────────────────────┘
        gpt-5.5 (cloud)  ·  robot_lab Network          qwen/qwen3.8-27b (local LM Studio)
```

This is the natural progression from
[01_basic_usage](../01_basic_usage/): there the acceptance tests were hardcoded;
here they are **generated collaboratively** — the Planner (a different robot than
the implementer) writes the spec, so the implementer still can't game it.

## What each phase demonstrates

| Phase | robot_lab feature | Model |
|-------|-------------------|-------|
| 1 — Ideate | `AskUser` tool, network task, templated robot | OpenAI `gpt-5.5` |
| 2 — Plan | sequential network `task … depends_on`, data hand-off, file tools | OpenAI `gpt-5.5` |
| 3 — Implement | `RobotLab::To.run` autonomous loop, verify gate, `stop_when`, guardrails | local LM Studio `qwen/qwen3.8-27b` |

The reasoning phases run on a capable cloud model; the implementation loop runs
fully local. Because both use RubyLLM's `:openai` provider but different endpoints
(`api.openai.com` vs LM Studio's `/v1`), and `openai_api_base` is global, the example
toggles it between the sequential phases.

## The quality gate

The implementer's `--verify-command` is `ruby quality_gate.rb`, which aggregates
four checks and commits an iteration only when **all** pass:

```
quality gate:
  ✓ tests    the Planner-authored acceptance suite (test/**/*_test.rb)
  ✓ rubocop  no style offenses in lib/
  ✓ flog     no method more complex than FLOG_MAX (default 25)
  ✓ flay     structural-duplication mass below FLAY_MAX (default 40)
→ PASS
```

So the robot must earn each commit on **correctness *and* quality** — it can't
ship working-but-ugly code. This turns `robot_lab_project`'s own bar (rubocop +
flog + flay) into an autonomous gate. Tune the thresholds with `FLOG_MAX` /
`FLAY_MAX`.

## Prerequisites

```bash
export OPENAI_API_KEY="sk-..."     # ideation + planning (gpt-5.5)
```

`common.rb` starts the LM Studio server and loads the build model itself if
they aren't already running/loaded, so there's nothing to start by hand for
the implementation phase.

## Run it

```bash
bundle exec ruby examples/02_advanced_usage/advanced_usage.rb
```

It is **interactive** — the Ideator will ask you, at the terminal, what to build
and a few clarifying questions. Answer them, then watch the Planner write the
acceptance suite and the local model implement it.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `RLTO_REASON_MODEL` | `gpt-5.5` | model for ideate + plan |
| `RLTO_REASON_PROVIDER` | `openai` | provider for ideate + plan |
| `RLTO_BUILD_PROVIDER` | `lms` (falls back to `RLTO_PROVIDER`) | provider label for implementation; `lms` resolves to `:openai` routed at `LMS_BASE_URL` |
| `RLTO_BUILD_MODEL` | `qwen/qwen3.8-27b` (falls back to `RLTO_MODEL`) | model for implementation |
| `LMS_BASE_URL` | `http://localhost:1234/v1` | LM Studio OpenAI-compatible endpoint |
| `FLOG_MAX` | `25` | per-method complexity ceiling |
| `FLAY_MAX` | `40` | duplication-mass ceiling |

## Layout

Everything stays under `examples/02_advanced_usage/` (both git-ignored, recreated
each run):

```
examples/02_advanced_usage/
├── advanced_usage.rb     # the orchestration
├── quality_gate.rb       # seeded into the project as the verify command
├── project/              # the throwaway git repo the agents work in
└── .robot_lab_to/        # the implementation run's logs + notes.md
```

## Live feedback

Narration of every robot's action across all three phases comes from robot_lab
core — **`RobotLab::Narrator`** — enabled with a single line:

```ruby
RobotLab::Narrator.enable!   # registers globally; covers the network + the -to loop
```

```
  · ideator: thinking…
  · → robot_lab--ask_user question="What tiny Ruby library would you like to build?…"
  · planner: thinking…
  · → write path="test/temperature_converter_test.rb"
  · → bash command="ruby quality_gate.rb"
```

This replaces the hand-written `RobotLab::Hook` that earlier examples used — a
~60-line hook became one call. The Narrator writes to `$stderr` (not `Kernel#warn`,
which is silenced when `$VERBOSE` is `nil` under `bundle exec`). For richer
per-tool output (icons, shell exit codes) you can subclass `RobotLab::Narrator`
and override `before_tool_call` / `after_tool_call`.
