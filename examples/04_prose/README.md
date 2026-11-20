# 04 — Prose: split the doer from the verifier

Demo 03 scores **code** with a deterministic command (passing tests). Prose has no
`rake coverage`, so this demo uses the **`prose` eval** — a pairwise LLM judge — and
puts two roles on the same local model by default, each independently swappable:

| Role | Model (default) | Job |
|------|-----------------|-----|
| **Doer** | `qwen/qwen3.8-27b` | writes and improves `guide.md` |
| **Verifier** (judge) | `qwen/qwen3.8-27b` | compares each draft to the last committed one and rules it **better / worse / same** |

Only a draft the judge rules **better** is committed, so every commit is a genuine
improvement. There's no absolute target (LLM scores are too noisy to descend), so
the run ends on `--stop-on-plateau` (N drafts with no improvement) or max
iterations. The spec (`outline.md`) is **locked** with `--protect-path` — the doer
cannot edit the criteria it's judged against.

## Run it

```bash
bundle exec ruby examples/04_prose/prose_run.rb
```

`common.rb` starts the LM Studio server and loads the doer + judge models for
you if they aren't already running/loaded. Override the models via env:
`RLTO_MODEL` (doer), `RLTO_JUDGE_MODEL` (verifier).

## Why the judge can be the same model as the doer

The **doer** is given the file-editing tools; the **judge** is given **no tools**
at all — it just reads two versions and replies `better`/`worse`/`same`. As a pure
text responder it doesn't need to be a stronger or different model to be reliable,
which is why both roles default to the same local `qwen/qwen3.8-27b`. This is still the
separation-of-duties payoff: the model that *decides* is called independently of
the model that *acts*, so swap in a stronger `RLTO_JUDGE_MODEL` if you want a
tougher judge without touching the doer.

## The mechanism

`RobotLab::To.run(..., eval: "prose", eval_judge_model: "qwen/qwen3.8-27b")` builds an
`Evals::Prose`. Each iteration, after the doer edits `guide.md`, the eval diffs the
working tree against the parent commit, shows both versions plus the spec to the
judge model, and maps its verdict onto `Score#improved`. Commit on *better*, roll
back otherwise.
