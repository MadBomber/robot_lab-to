# 04 — Prose: split the doer from the verifier

Demo 03 scores **code** with a deterministic command (passing tests). Prose has no
`rake coverage`, so this demo grades with an LLM judge instead — through two
**custom evals** (`OutlineGrader` and `SectionGrader` in
[`prose_run.rb`](prose_run.rb), both `RobotLab::To::Evals::Base` subclasses) — and
puts two roles on the same local model by default, each independently swappable:

| Role | Model (default) | Job |
|------|-----------------|-----|
| **Doer** | `qwen/qwen3.8-27b` | writes `outline.md`, then one `sections/NN_*.md` file per iteration |
| **Verifier** (judge) | `qwen/qwen3.8-27b` | grades each artifact **READY** or **NEEDS_WORK** (with feedback) |

The work runs as two `RobotLab::To.run` calls:

1. **Outline** — the doer writes `outline.md`; the run ends (`met_target`) when
   the judge grades it READY, or after 6 iterations.
2. **Sections** — one section file per iteration; the run ends when every outline
   section has a file and the latest is READY, or at its iteration cap.

The approved sections are then assembled into `guide.md`. The judge's feedback is
written to `REVIEW.md` (git-ignored in the sandbox) for the doer to read on its
next iteration. Both runs pass `require_improvement: false`, so every iteration
the doer reports as successful is committed, and `write_guard: false`, so the
doer can rewrite the file it is refining.

## Run it

```bash
bundle exec ruby examples/04_prose/prose_run.rb
```

`common.rb` starts the LM Studio server and loads the doer + judge models for
you if they aren't already running/loaded. Override the models via env:
`RLTO_MODEL` (doer), `RLTO_JUDGE_MODEL` (verifier); `RLTO_TOPIC` sets the subject
(default: "writing good Git commit messages").

## Why the judge can be the same model as the doer

The **doer** is given the file-editing tools; the **judge** is given **no tools**
at all — it just reads the artifact and its criteria and replies `READY` or
`NEEDS_WORK: <feedback>`. As a pure
text responder it doesn't need to be a stronger or different model to be reliable,
which is why both roles default to the same local `qwen/qwen3.8-27b`. This is still the
separation-of-duties payoff: the model that *decides* is called independently of
the model that *acts*, so swap in a stronger `RLTO_JUDGE_MODEL` if you want a
tougher judge without touching the doer.

## The mechanism

`RobotLab::To.run(objective, eval: OutlineGrader.new(work_dir: sandbox), ...)` hands
the orchestrator a custom eval. Each iteration, after the doer writes, the eval
reads the artifact, asks the judge robot (built from the `judge` template in
`prompts_dir/`) for a verdict against the criteria template, and returns a `Score`
with `gate_ok: true, improved: true` and `met_target` set when the phase is done.

For the built-in *pairwise* judge instead — `eval: "prose"` / `--eval prose`, which
compares each draft with the last committed version and commits only on *better*
— see [03_scored](../03_scored/README.md#2-prose--pairwise-judgement).
