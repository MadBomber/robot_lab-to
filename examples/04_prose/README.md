# 04 — Prose: split the doer from the verifier

Demo 03 scores **code** with a deterministic command (passing tests). Prose has no
`rake coverage`, so this demo uses the **`prose` eval** — a pairwise LLM judge — and
puts two *different* models in two roles:

| Role | Model (default) | Job |
|------|-----------------|-----|
| **Doer** | `qwen3.6:latest` | writes and improves `guide.md` |
| **Verifier** (judge) | `gpt-oss:latest` | compares each draft to the last committed one and rules it **better / worse / same** |

Only a draft the judge rules **better** is committed, so every commit is a genuine
improvement. There's no absolute target (LLM scores are too noisy to descend), so
the run ends on `--stop-on-plateau` (N drafts with no improvement) or max
iterations. The spec (`outline.md`) is **locked** with `--protect-path` — the doer
cannot edit the criteria it's judged against.

## Run it

```bash
ollama pull qwen3.6:latest      # doer
ollama pull gpt-oss:latest      # verifier / judge
bundle exec ruby examples/04_prose/prose_run.rb
```

Override the models via env: `RLTO_MODEL` (doer), `RLTO_JUDGE_MODEL` (verifier).

## Why gpt-oss works as the judge here (but not as a doer)

gpt-oss is a reasoning model that, when *offered tools*, tends to call its own
built-ins (`container.exec`) instead of the provided ones — which makes it a poor
**doer**. But the **judge** is given **no tools**; it just reads two versions and
replies `better`/`worse`/`same`. As a pure text responder it's reliable, which is
exactly the verifier's job. This is the separation-of-duties payoff: the model that
*decides* is independent of the model that *acts*.

## The mechanism

`RobotLab::To.run(..., eval: "prose", eval_judge_model: "gpt-oss:latest")` builds an
`Evals::Prose`. Each iteration, after the doer edits `guide.md`, the eval diffs the
working tree against the parent commit, shows both versions plus the spec to the
judge model, and maps its verdict onto `Score#improved`. Commit on *better*, roll
back otherwise.
