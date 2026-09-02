# robot_lab-to is a plain Ruby gem (RobotLab::To), not a Rails app -- there is
# no app/ tree, no controllers/models/views, so the :rails preset doesn't
# apply. These are the actual boundaries documented in CLAUDE.md.

# Matched by exact constant, not a file glob: every file here reopens the
# bare `module RobotLab` namespace (shared with the external robot_lab gem's
# own top-level module), so an `in:` glob would misattribute any bare
# `RobotLab.xxx` call anywhere in the gem to this component.
component :orchestrator, constants: "RobotLab::To::Orchestrator"
component :tools, in: "lib/robot_lab/to/tools/**/*.rb"
component :guards, in: %w[lib/robot_lab/to/guards.rb lib/robot_lab/to/guards/**/*.rb]
component :evals, in: "lib/robot_lab/to/evals/**/*.rb"
component :commit_manager, in: "lib/robot_lab/to/commit_manager.rb"

# Tools are RobotLab::Tool subclasses the robot calls mid-turn (see
# lib/robot_lab/to/tools/file_tool.rb); Guards are RobotLab::Hook subclasses
# wired onto a robot by Orchestrator#build_robot; Evals are "orchestrator-owned
# scorers" per CLAUDE.md. All three are built and consumed by the orchestrator
# -- the dependency runs one way, never back into the loop that drives them.
tools.cannot_use :orchestrator,
                 because: "tools run inside an LLM turn, invoked by the robot -- " \
                          "they must not reach back into the loop that drives them"
guards.cannot_use :orchestrator,
                  because: "guards are wired onto a robot by Orchestrator#build_robot -- " \
                           "the dependency runs one way"
evals.cannot_use :orchestrator,
                 because: "evals are orchestrator-owned scorers (CLAUDE.md) -- " \
                          "Orchestrator calls Evals.build, not the reverse"

# CLAUDE.md: "CommitManager -- all git ops via Open3.capture3 (no shell
# interpolation)". Enforce the "no shell interpolation" half architecturally.
commit_manager.cannot_call :system, receiver: :none,
                           because: "git ops must go through Open3.capture3 with an argv array, " \
                                    "never system()/backticks with an interpolated string"
