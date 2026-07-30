# Cross-Iteration Memory (`notes.md`)

Each iteration runs a **fresh** robot with no memory of previous iterations. The
only thing that carries forward is `notes.md` — a human-readable log the
orchestrator maintains and injects into every iteration's system prompt.

This is what lets the loop make progress instead of repeating the same attempt.

## Who writes it, who reads it

- **The orchestrator writes it.** After every iteration it appends an entry
  (success, failure, verify-failure, or error).
- **The robot reads it.** The `PromptBuilder` embeds the current notes into the
  system prompt under a "Prior Work" section.
- **The robot must not edit it.** The prompt explicitly tells the robot that
  `notes.md` is maintained automatically. Writes are atomic (`AtomicFile`).

## Location

```
.robot_lab_to/runs/<run_id>/notes.md
```

The path is also passed to the robot in the prompt so it can read the file
directly if it has file tools.

## Structure

The file starts with a header and grows one section per iteration:

```markdown
# robot-to run: 20260623-144554-3e5c27

Objective: Migrate the codebase from Minitest to RSpec

## Iteration Log

### Iteration 1

**Summary:** Converted spec_helper and the parser tests to RSpec

**Changes:**
- spec/spec_helper.rb
- spec/parser_spec.rb

**Learnings:**
- The project uses `assert_equal`; RSpec equivalent is `expect(x).to eq(y)`

### Iteration 2 [FAIL]

**Summary:** Attempted to convert the integration tests but broke the suite

**Learnings:**
- The integration tests depend on a Rack test helper not yet ported
```

## Entry types

| Marker | When | Includes |
|--------|------|----------|
| *(none)* | Successful, committed iteration | summary, changes, learnings |
| `[FAIL]` | Robot reported failure or didn't submit | summary, learnings |
| `[VERIFY FAILED]` | Robot claimed success but the eval's gate failed (`--verify-command` / `--floor`) | summary, gate output |
| `[NO IMPROVEMENT]` | Gate passed but the eval didn't rule it better than the parent commit (rolled back unless `--no-require-improvement`) | summary, score detail |
| `[ERROR]` | An exception was raised during the iteration | error class and message |

`[VERIFY FAILED]` and `[NO IMPROVEMENT]` come from the [Evals](evals.md) scoring
gate, not the robot — see there for how `gate_ok` and `improved` are decided.

Because failures and their learnings are recorded too, the next robot can avoid
repeating a dead end — the failure log is as valuable as the success log.

## Designing objectives around the notes

The notes are most effective when:

- The objective is a single, clear goal the robot can chip away at.
- Each iteration is genuinely incremental — "make ONE focused change" is baked
  into the prompt.
- `key_learnings` capture *transferable* facts ("the build uses esbuild, not
  webpack"), not restatements of the diff.

You can read the notes live during a run to watch the robot's reasoning evolve:

```bash
tail -f .robot_lab_to/runs/*/notes.md
```

---

Next: [Stop Conditions](stop-conditions.md).
