# Verification Gate

A robot reporting `success: true` is a *claim*, not a fact. The verification gate
makes that claim count only when an independent command — one you choose — agrees.

This is separation of duties applied to a single agent: the **robot does the
work**, but the **orchestrator runs the deciding command**. The robot cannot
self-certify a passing verdict.

## Enabling it

```bash
robot-to "Fix the failing parser tests" \
  --verify-command "bundle exec rake test" \
  --verify-timeout 600
```

When `--verify-command` is set, every iteration the robot marks successful is
gated:

```
robot says success ──► run verify-command ──► exit 0 ? ──► COMMIT
                                                 │
                                                 │ non-zero / timeout
                                                 ▼
                                              ROLLBACK  (recorded as [VERIFY FAILED])
```

If verification fails, the working tree is reset with `git reset --hard`, the
iteration counts as a failure (incrementing the consecutive-failure counter), and
the verification output is written to `notes.md` so the next robot can see *why*
it failed.

## How it runs

The `Verifier`:

- Runs the command in the project working directory via `Open3.popen2e`.
- Launches it in its own **process group** so a timeout can kill the whole
  process tree — test runners that spawn children won't survive a timeout.
- Enforces `--verify-timeout` seconds (default **600**). On timeout the process
  group is terminated and the gate fails.
- Captures combined stdout+stderr, clamped to ~4 000 characters for the notes.

A non-zero exit **or** a timeout fails the gate.

## Choosing a verify command

The command should be the real signal of correctness for your objective:

| Objective | Good `--verify-command` |
|-----------|-------------------------|
| Fix failing tests | `bundle exec rake test` |
| Keep the build green | `npm run build` |
| Don't regress lint | `bundle exec rubocop` |
| Full quality bar | `bundle exec rake` (tests + lint + coverage) |

Tips:

- Make it **fast enough to run every iteration** — it runs on each claimed
  success.
- Make it **deterministic** — flaky commands cause spurious rollbacks.
- Combine checks with `&&` if you want several gates: `--verify-command "bundle
  exec rake test && bundle exec rubocop"`.

## Without a verify command

If you don't set `--verify-command`, the robot's self-reported `success` is taken
at face value and committed. This is fine for low-risk objectives (docs,
comments, scaffolding) but for anything that must keep working, a verification
gate is strongly recommended.

---

Next: [Run State & Event Log](run-state.md).
