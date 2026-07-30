# Quick Start

This walkthrough takes you from a clean repository to a finished overnight run.

## 1. Start in a git repository with a commit

```bash
cd my-project
git status            # must be a git repo
git log --oneline     # must have at least one commit
```

If there are no commits yet:

```bash
git commit --allow-empty -m "initial"
```

## 2. Run a bounded objective

Give `robot-to` a clear, single-sentence objective and a stop condition. Keep
the first run small and bounded so you can watch it work:

```bash
robot-to "Add a CHANGELOG.md and document the public API in the README" \
  --max-iterations 5 \
  --provider anthropic \
  --model claude-sonnet-4-6
```

What happens:

- A branch `robot-to/<slugified-objective>-<timestamp>` is created.
- For up to 5 iterations, a fresh robot makes one focused change and reports a
  result.
- Each successful iteration becomes one commit on the branch.
- Failures are rolled back (`git reset --hard`) and recorded in the notes.

## 3. Add an independent verification gate

The robot's self-reported success only counts if a command **you** choose
passes. This is the single most important flag for unattended runs:

```bash
robot-to "Fix the failing tests in spec/parser" \
  --verify-command "bundle exec rake test" \
  --max-iterations 15 \
  --max-consecutive-failures 4
```

If `--verify-command` exits non-zero (or times out), the iteration is rolled
back even though the robot claimed success. See [Verification Gate](../concepts/verification.md).

## 4. Let it stop itself

For a true overnight run, combine a hard ceiling with a natural-language stop
condition:

```bash
robot-to "Migrate the codebase from Minitest to RSpec" \
  --verify-command "bundle exec rake" \
  --max-iterations 50 \
  --max-tokens 2000000 \
  --stop-when "all test files are RSpec and the suite passes"
```

The robot evaluates `--stop-when` after each successful iteration and sets
`should_fully_stop` when it judges the condition met. See
[Stop Conditions](../concepts/stop-conditions.md).

## 5. Review in the morning

```bash
git log --oneline robot-to/migrate-the-codebase-from-...   # the iteration history
git diff main..HEAD                                         # the full change
cat .robot_lab_to/runs/*/notes.md                           # the reasoning log
```

Each commit is one iteration. Squash, cherry-pick, or reset as you like — it's
an ordinary branch.

## Programmatic use

You can also drive a run from Ruby instead of the CLI:

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

`RobotLab::To.run(objective, **opts)` accepts the same options as the CLI flags
(as keyword arguments). See the [Settings Reference](../configuration/settings.md).

---

Next: understand exactly what one run produces in
[Anatomy of a Run](anatomy-of-a-run.md).
