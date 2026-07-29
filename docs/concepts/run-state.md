# Run State & Event Log

Everything a run produces — besides the git commits — lives under a single run
directory. This page documents that layout and the JSONL event log.

## Run directory layout

```
.robot_lab_to/
└── runs/
    └── <run_id>/                 # e.g. 20260623-144554-3e5c27
        ├── notes.md              # human-readable cross-iteration memory
        ├── run.log               # JSONL event log (one event per line)
        └── checkpoints/          # pre-edit file snapshots (local_guards only)
```

- `<run_id>` is `YYYYMMDD-HHMMSS-<random hex>`.
- The whole `.robot_lab_to/` directory is added to `.git/info/exclude` at startup,
  so it never appears in `git status` or commits.
- Change `--run-dir` to relocate it (default `.robot_lab_to`).

## The JSONL event log (`run.log`)

`run.log` contains one JSON object per line — a structured, append-only trace of
the run. Every line has an `event` name and a UTC `ts` timestamp; other keys
depend on the event. The logger buffers up to 100 events before the file is open,
so the very first setup events are never lost.

A typical successful iteration:

```json
{"event":"orchestrator:start","ts":"2026-06-23T14:45:54.001-05:00","run_id":"20260623-144554-3e5c27","objective":"...","branch":"robot-to/...","model":"claude-sonnet-4-6"}
{"event":"iteration:start","ts":"...","iteration":1}
{"event":"agent:run:start","ts":"...","iteration":1}
{"event":"agent:run:end","ts":"...","iteration":1}
{"event":"eval","ts":"...","iteration":1,"gate":true,"improved":true,"value":null,"met_target":false,"detail":"verify=true"}
{"event":"commit:success","ts":"...","iteration":1,"message":"robot-to 1: ..."}
```

### Event reference

| Event | Meaning |
|-------|---------|
| `orchestrator:start` | Run began. Carries `run_id`, `objective`, `branch`, `model`. |
| `orchestrator:resume` | A `--resume` re-entered the loop (`run_id`, `iteration`, `branch`). |
| `iteration:start` | A new iteration began. |
| `agent:run:start` / `agent:run:end` | The robot's `run` call started / finished. |
| `agent:nudge` | The robot didn't submit; re-asking (`attempt` N). |
| `agent:run:error` | An exception occurred during the iteration (`error`, `message`). |
| `backoff:start` / `backoff:end` | Retry backoff sleep around a transient error. |
| `eval` | The [eval's](evals.md) verdict for this iteration: `gate`, `improved`, `value`, `met_target`, `detail`. |
| `eval:repair` | R2 repair attempt after a gate failure (`attempt` N of `--max-verify-repairs`). |
| `eval:repair_error` | The repair attempt itself raised (`message`); repair loop stops. |
| `commit:success` | Iteration committed (`message`). |
| `commit:failed` | `git commit` failed; queued for repair (`output`). |
| `iteration:failure` | Robot reported failure or never submitted (`summary`). |
| `iteration:gate_failure` | Robot claimed success but the eval's gate failed (recorded in notes as `[VERIFY FAILED]`). |
| `iteration:no_improvement` | Gate passed but the eval didn't rule it an improvement (`detail`); rolled back. |
| `orchestrator:abort` | Run stopped by a stop condition, `met_target`, or permanent error (`reason`). |
| `orchestrator:fatal` | Unexpected fatal error (`error`, `message`). |
| `orchestrator:end` | Final totals: `iterations`, `commits`, `input_tokens`, `output_tokens`, `abort_reason`, `elapsed`. |

Decision-file events (`decision:blocking`, `decision:wait:start`,
`decision:wait:resolved`, `decision:raised`) are also written when decisions are
enabled — see the README's Human-in-the-Loop section.

### Analyzing a run

Because every line is JSON, the log is easy to query with
[`jq`](https://stedolan.github.io/jq/):

```bash
# Watch events live, formatted
tail -f .robot_lab_to/runs/*/run.log | jq -r '"\(.ts)  \(.event)"'

# How many iterations committed vs failed?
jq -r 'select(.event=="commit:success")' run.log | wc -l
jq -r 'select(.event=="iteration:failure") | .summary' run.log

# Final token usage
jq 'select(.event=="orchestrator:end") | {iterations,commits,input_tokens,output_tokens}' run.log
```

## Debug logging

By default, RubyLLM/RobotLab logging is suppressed so the console stays clean.
Pass `--debug` to keep verbose provider logging enabled (useful when diagnosing
provider or tool-call issues). The JSONL event log is always written regardless
of `--debug`.

---

Next: [Configuration](../configuration/index.md).
