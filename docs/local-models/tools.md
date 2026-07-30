# Built-in Tools

When `--local-guards` is enabled, the per-iteration robot is given a small set of
built-in workspace tools in addition to `submit_iteration_result`. They are
named with short, conventional names (`read`, `write`, `edit`, `bash`) — small
models do measurably better with short tool names than with long namespaced ones.

!!! note "Why these are bundled"
    Without file tools, a robot can only *report* — it can't change code. The
    built-in tools give a local model a predictable, guarded surface to do real
    work. With a cloud model you'd typically supply richer tools yourself; these
    are a dependable baseline for the local-assistant use case.

## The tools

### `read`

Read a UTF-8 text file, optionally a line range.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `path` | yes | File to read. |
| `offset` | no | 1-based first line to return. |
| `limit` | no | Maximum number of lines to return. |

Output is capped (2 000 lines) so one oversized read can't blow a small model's
context, and a truncation note tells the model how to read more. Reading a file
also satisfies the [read-before-edit](guardrails.md#read-before-edit) guard.

### `write`

Create a **new** file. Parent directories are created as needed.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `path` | yes | File to create. |
| `content` | yes | Full text content. |

`write` is for new files only. The [write-guard](guardrails.md#write-guard)
refuses it on a file that already exists and redirects the model to `edit` — small
models otherwise rewrite whole files and lose content.

### `edit`

Exact-string replacement in an existing file.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `path` | yes | File to edit. |
| `old_text` | yes | Exact text to replace (whitespace included). |
| `new_text` | yes | Replacement text. |
| `replace_all` | no | Replace every occurrence (default false). |

`old_text` must match the current file contents exactly and be unique unless
`replace_all` is set; otherwise the edit is refused with a clear message. The
[read-before-edit](guardrails.md#read-before-edit) guard requires the file to have
been `read` this run first, so `old_text` reflects the real contents rather than a
guess.

### `bash`

Run a shell command in the project directory.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `command` | yes | Shell command to run. |
| `timeout` | no | Seconds before the command is killed (default 120). |

Returns combined stdout+stderr and the exit status (`[exit 0]\n...`). Output is
capped (~30 000 chars) and a runaway process is killed at the timeout so it can't
stall an overnight loop.

## How they're wired in

The orchestrator builds them per iteration and attaches them through RobotLab's
`local_tools:`:

```ruby
# only when local_guards is on
[submit_tool, Tools::Read.new, Tools::Write.new, Tools::Edit.new, Tools::Bash.new]
```

Without `--local-guards`, the robot gets only `submit_iteration_result` — you're
expected to supply your own tools (typical for cloud-model setups).

The short names come from a small `FileTool` base class that overrides RubyLLM's
default namespaced tool name. The guardrail hooks match on exactly these names
(`read`/`write`/`edit`/`bash`).

---

Next: [Guardrails](guardrails.md).
