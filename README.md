<div align="center">
  <img src="docs/assets/images/robot_lab-to.jpg" alt="robot_lab-to" width="320"><br />
  "Robot, takeover!"
</div>

# robot_lab-to

**Autonomous overnight agent loop for [RobotLab](https://github.com/MadBomber/robot_lab) — run a robot while you sleep.**

`robot_lab-to` ("takeover") runs a RobotLab `Robot` in an autonomous loop toward a
stated objective, committing **one focused change per iteration**. Each iteration
spins up a fresh robot, lets it work, and asks it to report a result. Good
iterations are committed; failures are rolled back. A running log (`notes.md`)
carries memory across iterations so the robot learns from what came before.

Start it before bed; review the branch in the morning.

```bash
robot-to "Increase test coverage of the parser to 90%" \
  --max-iterations 20 \
  --verify-command "bundle exec rake test"
```

> 📖 **Full documentation:** <https://madbomber.github.io/robot_lab-to>

---

## How it works

Every iteration is an independent, sandboxed attempt at *one* improvement. The
orchestrator owns the git history and the stop conditions; the robot owns the
work.

1. **Build a fresh robot** with a per-iteration system prompt that includes the
   objective and the accumulated notes.
2. **The robot works** and calls `submit_iteration_result` to report success or
   failure.
3. **The orchestrator decides** — an independent `--verify-command` (if set) must
   pass, then the change is committed. Otherwise the working tree is reset
   (`git reset --hard`).
4. **Notes are updated** with what happened, becoming context for the next round.
5. **Stop conditions are checked** — iterations, tokens, consecutive failures, or
   a natural-language `--stop-when` — and the loop continues or ends.

---

## Scoring: evals

By default a "good" iteration is one the robot *reports* as success (and that
passes `--verify-command`, if set). That works for "don't break the build," but it
can't answer *"is this actually better?"* — and an agent will happily report
success on a change that made no real progress. An **eval** replaces the robot's
self-report with an orchestrator-owned, measurable judgement, and makes the loop
**descend toward a target** instead of merely not-breaking.

Two built-in evals cover the two kinds of product.

### Code — measured descent

For software, "better" is measurable. Give the loop a **measure** command that
prints a number (higher = better), and optionally a **target**:

```bash
robot-to "Raise parser coverage to 90%" \
  --verify  "bundle exec rake test" \      # floor: must stay green (correctness)
  --measure "bundle exec rake coverage" \  # descent signal (higher = better)
  --target  90                             # stop once the score reaches this
```

An iteration is committed only if it **improves** the measured score *and* the
verify floor still passes; a change that scores no better is rolled back, so the
branch descends monotonically and the run stops itself when the target is met.
Relax the monotonic gate with `--no-require-improvement`.

### Prose — pairwise judgement

For a document, an opinion piece, or a book there is no `rake coverage`. The
**prose** eval scores each draft with an LLM judge that compares it *pairwise*
against the last committed version — an LLM's absolute scores are too noisy to
descend, but "is B better than A?" is reliable:

```bash
robot-to "Write an opinionated guide to the Viable Systems Model" \
  --eval  prose \
  --spec  outline.md \          # the spec the judge measures against
  --floor "rake docs:lint" \    # optional mechanizable checks (links, TODOs)
  --stop-on-plateau 3           # stop after 3 drafts with no improvement
```

A draft is committed only when the judge rules it **better** than its parent.
There is no absolute target, so the run ends on `--stop-on-plateau` (N drafts with
no improvement) or when you stop it.

### Guarding the grader

Whatever the eval, the robot must not be able to "win" by editing the criteria it
is scored against. The **spec** and any `--protect-path` files are locked for the
whole run — write/edit/bash attempts against them are refused. (The code test
suite is deliberately *not* locked; adding tests is legitimate work.)

### Custom evals

Point `--eval` at a strategy registered with `RobotLab::To.register_eval`, or in
Ruby pass any object responding to `#score(context)` (or a proc) as `eval:`. See
`RobotLab::To::Evals::Base`.

---

## Human-in-the-loop: decision files

The loop runs unattended, so it can't stop and ask you a question the way a chat
agent can. Instead, when the robot hits a choice it **shouldn't make on its own**
— an irreversible change, a public API contract, a genuine ambiguity about intent
— it calls `request_decision` and the orchestrator writes a **decision file**:
the situation, the options, and the robot's own recommendation (its "lean").

A decision file is plain markdown with YAML front matter, under the run directory:

```markdown
---
id: d-20260701-143022-a1b2c3
status: pending          # you change this to: resolved
blocking: true
resolution:              # you fill this in
---
# Decision: Return 404 or 410 for deleted records?

## Options
1. 404 Not Found
2. 410 Gone

## Recommendation (robot's lean)
Option 2 (410 Gone) — the records are permanently deleted...
```

You resolve it out-of-band by editing the file: set `status: resolved` and fill
`resolution:`. The robot reads your answer on a later iteration and acts on it.

List what's waiting on you:

```bash
robot-to decisions              # pending decisions for the latest run
robot-to decisions <run_id>     # ...for a specific run
```

**Blocking decisions** gate the loop until you answer, in one of two modes:

- `--decision-mode wait` (default) — the process stays alive and polls the
  decision file until you resolve it (or `--decision-timeout` elapses).
- `--decision-mode exit` — the process commits its safe work and **stops**,
  telling you how to resume. Ideal for cron: nothing runs until you decide.

### Resuming a run (and cron scheduling)

Every run persists its state to `run.json`, so a stopped run can be continued on
the same branch:

```bash
robot-to --resume <run_id>
```

This makes `robot_lab-to` schedulable — a cron entry that runs
`robot-to --resume <run_id>` each hour advances the work or re-pauses on the next
open decision, one commit at a time.

---

## Installation

Requires **Ruby >= 3.2** and a git repository with at least one commit.

```bash
gem install robot_lab-to
```

Or in a `Gemfile`:

```ruby
gem "robot_lab-to"
```

This installs the `robot-to` executable.

---

## Quick start

```bash
cd my-project
git commit --allow-empty -m "initial"   # the loop needs a HEAD to branch from

robot-to "Add a CHANGELOG.md and document the public API in the README" \
  --max-iterations 5 \
  --provider anthropic \
  --model claude-sonnet-4-6
```

The loop creates a `robot-to/<slug>-<timestamp>` branch and commits one focused
change per successful iteration. Review it in the morning:

```bash
git log --oneline robot-to/...     # one commit per iteration
git diff main..HEAD                # the full change
cat .robot_lab_to/runs/*/notes.md  # the reasoning log
```

### Programmatic use

```ruby
require "robot_lab"
require "robot_lab/to"

RobotLab::To.run(
  "Add a CHANGELOG.md and document the public API",
  provider: :anthropic,
  model: "claude-sonnet-4-6",
  max_iterations: 5,
  verify_command: "bundle exec rake test"
)
```

---

## Key features

- **Bounded, reviewable history** — each iteration is a single commit; bad
  attempts are reset before the next try.
- **Cross-iteration memory** — `notes.md` records summaries, changes, and
  learnings so the robot doesn't repeat itself.
- **Independent verification** — the robot can't self-certify success; a real
  command you choose (`--verify-command`) is the deciding authority.
- **It stops on its own** — `--max-iterations`, `--max-tokens`,
  `--max-consecutive-failures`, and a natural-language `--stop-when`.
- **Asks before overstepping** — the robot escalates irreversible or ambiguous
  choices as **decision files** you resolve out-of-band, instead of guessing.
- **Resumable & cron-friendly** — run state is persisted to `run.json`;
  `robot-to --resume <run_id>` continues a stopped run, so an external scheduler
  can drive it one commit per tick.
- **Runs on local models** — with `--local-guards` it ships built-in file tools
  and small-model guardrails to drive a local Ollama model offline.

---

## Local models

`robot_lab-to` can drive a local model running offline against
[Ollama](https://ollama.com) — no API keys, no per-token cost.

```bash
ollama pull gpt-oss:20b

robot-to "Add a greet(name) method in greeter.rb" \
  --provider openai \
  --model gpt-oss:20b \
  --local-guards \
  --no-stream \
  --max-iterations 5
```

`--local-guards` attaches built-in `read`/`write`/`edit`/`bash` tools plus
guardrail hooks (`write-guard`, `read-before-edit`, `checkpoint`,
`quality-monitor`) adapted from [`little-coder`](https://github.com/itayinbarr/little-coder)
that catch the mistakes small models reliably make. `--no-stream` is required —
Ollama suppresses tool calls when streaming, and `:openai` is used as the
provider against Ollama's OpenAI-compatible endpoint.

See the [Local Models guide](https://madbomber.github.io/robot_lab-to/local-models/)
for the full setup, including the RubyLLM configuration and model selection.

---

## Configuration

Settings cascade from lowest to highest precedence:

```
bundled defaults → ~/.config/robot_lab/to.yml → ROBOT_LAB_TO_* env → CLI flags
```

Run `robot-to --help` for all flags, or see the
[Configuration reference](https://madbomber.github.io/robot_lab-to/configuration/settings/).

### Environment variables

Every persistent setting can be set with a `ROBOT_LAB_TO_*` environment variable
(integers and booleans are coerced automatically). An env var overrides the
bundled default and the user config file, but is overridden by a CLI flag.

| Environment variable | Setting | Default |
|----------------------|---------|---------|
| `ROBOT_LAB_TO_PROVIDER` | LLM provider | `openai` |
| `ROBOT_LAB_TO_MODEL` | Model identifier | `gpt-5.5` |
| `ROBOT_LAB_TO_STREAM` | Stream responses (`--no-stream` to disable) | `true` |
| `ROBOT_LAB_TO_LOCAL_GUARDS` | Attach file tools + small-model guardrails | `false` |
| `ROBOT_LAB_TO_MAX_TOOL_ROUNDS` | Max tool-call rounds per iteration | `100` |
| `ROBOT_LAB_TO_MAX_CONSECUTIVE_FAILURES` | Abort after N consecutive failures | `3` |
| `ROBOT_LAB_TO_MAX_VERIFY_REPAIRS` | Repair-in-place attempts on verify failure | `2` |
| `ROBOT_LAB_TO_MAX_RETRIES` | Retries for transient (e.g. API) errors | `2` |
| `ROBOT_LAB_TO_MAX_SUBMIT_NUDGES` | Re-prompts when no result is submitted | `1` |
| `ROBOT_LAB_TO_VERIFY_TIMEOUT` | Timeout (seconds) for `--verify-command` | `600` |
| `ROBOT_LAB_TO_COMMIT_FORMAT` | `default` or `conventional` | `default` |
| `ROBOT_LAB_TO_RUN_DIR` | Directory for run state | `.robot_lab_to` |
| `ROBOT_LAB_TO_DECISIONS_ENABLED` | Offer the `request_decision` tool | `true` |
| `ROBOT_LAB_TO_DECISION_MODE` | On a blocking decision: `wait` or `exit` | `wait` |
| `ROBOT_LAB_TO_DECISION_WAIT_POLL` | Seconds between polls while waiting | `30` |
| `ROBOT_LAB_TO_DEBUG` | Keep verbose provider logging enabled | `false` |

```bash
export ROBOT_LAB_TO_MODEL="gpt-oss:20b"
export ROBOT_LAB_TO_LOCAL_GUARDS=true
export ROBOT_LAB_TO_STREAM=false
```

> **Per-run settings have no env var.** `--max-iterations`, `--max-tokens`,
> `--stop-when`, `--verify-command`, and `--decision-timeout` are intentionally
> CLI-only (they default to "unset / no limit") and must be passed on the command
> line or to `RobotLab::To.run`.

### Provider credentials

API keys are read by the underlying provider (via RobotLab / RubyLLM), **not** by
`robot_lab-to` itself — e.g. `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`. Local
[Ollama](https://ollama.com) models need no key; see the
[Local Models guide](https://madbomber.github.io/robot_lab-to/local-models/ollama/).

---

## Development

```bash
bundle install             # install dependencies
bundle exec rake test      # run the test suite (SimpleCov coverage)
bundle exec rubocop        # lint
```

Documentation is built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/):

```bash
mkdocs serve               # preview at http://127.0.0.1:8000
mkdocs build               # render to site/
```

---

## Contributing

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/);
see `COMMITS.md`. See `CHANGELOG.md` for release history.

## License

Released under the [MIT License](https://opensource.org/licenses/MIT).
