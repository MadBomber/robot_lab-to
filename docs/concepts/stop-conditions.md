# Stop Conditions

Because `robot-to` is meant to run unattended, it must reliably stop on its own.
Four independent conditions can end a run; whichever trips first wins.

## The four conditions

| Condition | Flag | Checked | Effect |
|-----------|------|---------|--------|
| Max iterations | `--max-iterations N` | before & after each iteration | Stop after `N` iterations. |
| Max tokens | `--max-tokens N` | before & after each iteration (and mid-stream when streaming) | Stop once cumulative tokens reach `N`. |
| Consecutive failures | `--max-consecutive-failures N` | after each iteration | Abort after `N` failures in a row (default **3**). |
| Stop-when | `--stop-when "<text>"` | after each *successful* iteration | The robot judges the condition; sets `should_fully_stop`. |

If you set none of the bounded limits, the loop relies on
`--max-consecutive-failures` (default 3) and `--stop-when` to terminate. For a
genuinely unattended run, **always set at least `--max-iterations` or
`--max-tokens`.**

## How each works

### Max iterations

A simple counter. The run aborts with `max iterations reached (N)` once
`run.iteration >= N`.

### Max tokens

Cumulative input + output tokens across all iterations are compared against the
limit.

- **Streaming runs** (the default) account tokens per chunk and can interrupt an
  in-flight iteration the moment the budget is exhausted.
- **Non-streaming runs** (`--no-stream`, used for local models) account tokens
  from each iteration's result and stop at the next iteration boundary. See
  [Local Models](../local-models/ollama.md#streaming-and-tool-calls).

### Consecutive failures

Resets to zero on every successful, committed iteration; increments on every
failure, verify-failure, or commit-failure. This is the safety net that stops a
run that is going nowhere. The default is **3**.

### Stop-when (natural language)

`--stop-when` is a goal the robot evaluates. After a successful iteration, the
robot decides whether the condition is met and, if so, returns
`should_fully_stop: true` in its result. The orchestrator then aborts with
`stop condition met: <text>`.

```bash
robot-to "Refactor the auth module for clarity" \
  --max-iterations 30 \
  --stop-when "the auth module has no method longer than 15 lines and tests pass"
```

`--stop-when` only ends the loop on a **successful** iteration — a failing
iteration never triggers it, even if the robot thinks the goal is met.

## Graceful interruption

Pressing **Ctrl-C** (`SIGINT`) or sending `SIGTERM` requests a graceful stop: the
in-flight robot is interrupted, any pending backoff sleep is cancelled, the loop
exits, and the exit summary still prints. The current iteration's incomplete work
is rolled back.

## What you'll see

The exit summary header reports the reason:

```
robot-to stopped — claude-sonnet-4-6 — 41m 08s
Reason: max iterations reached (30)
```

Possible reasons include `max iterations reached (N)`, `max tokens reached (N)`,
`N consecutive failures`, `stop condition met: <text>`, a permanent error, or a
fatal error.

---

Next: [Verification Gate](verification.md).
