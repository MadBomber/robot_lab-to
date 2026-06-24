#!/usr/bin/env ruby
# frozen_string_literal: true

# ===========================================================================
# quality_gate.rb — aggregated correctness + quality gate
# ===========================================================================
#
# Seeded into the demo project and used as robot_lab-to's --verify-command. An
# iteration is only committed when ALL of these pass:
#
#   tests    the Planner-authored Minitest acceptance suite (test/**/*_test.rb)
#   rubocop  no style offenses in lib/ and test/
#   flog     no method more complex than FLOG_MAX
#   flay     structural duplication mass below FLAY_MAX
#
# So the robot must earn its commit on correctness AND quality — it can't ship
# working-but-ugly code. Prints a readable report and exits non-zero on any
# failure. Run from the project root.
# ===========================================================================

require "open3"
require "flog"
require "flay"
require "stringio"

FLOG_MAX = Integer(ENV.fetch("FLOG_MAX", "25")) # per-method complexity ceiling
FLAY_MAX = Integer(ENV.fetch("FLAY_MAX", "40")) # structural-duplication mass ceiling
LIB_GLOB = "lib/**/*.rb"

# Each gate returns [ok?, one-line detail].

def gate_tests
  files = Dir["test/**/*_test.rb"]
  return [false, "no test/**/*_test.rb files found"] if files.empty?

  requires = files.map { |f| "require './#{f}'" }.join("; ")
  out, status = Open3.capture2e("ruby", "-Ilib", "-Itest", "-rminitest/autorun", "-e", requires)
  summary = out[/\d+ runs?, .*?skips?/] || out.lines.last.to_s.strip
  [status.success?, summary]
end

# Lint only lib/ — the implementer's code. The Planner-authored tests in test/
# are the spec (graded by passing), not the implementer's to restyle.
#
# Pass explicit FILE paths (not the "lib" directory) and pin to the project's own
# .rubocop.yml: this demo project lives inside the robot_lab-to repo, whose
# .rubocop.yml excludes examples/** — so `rubocop lib` would inspect 0 files and
# falsely pass. Explicit paths bypass that inherited exclusion.
def gate_rubocop
  files = Dir[LIB_GLOB]
  return [true, "no lib/ to lint"] if files.empty?

  cmd = ["rubocop", "--format", "simple", "--no-color"]
  cmd += ["--config", ".rubocop.yml"] if File.exist?(".rubocop.yml")
  out, status = Open3.capture2e(*cmd, *files)
  detail = out[/\d+ files? inspected.*/] || "see rubocop output"
  [status.success?, detail]
end

def gate_flog
  files = Dir[LIB_GLOB]
  return [true, "no lib/ to analyze"] if files.empty?

  flog = Flog.new(continue: true)
  flog.flog(*files)
  worst_name, worst = flog.totals.max_by { |_, score| score } || [nil, 0.0]
  [worst <= FLOG_MAX, format("worst method %.1f (max %d)%s", worst, FLOG_MAX,
                             worst > FLOG_MAX ? " — #{worst_name}" : "")]
end

def gate_flay
  files = Dir[LIB_GLOB]
  return [true, "no lib/ to analyze"] if files.empty?

  flay = Flay.new
  flay.process(*files)
  flay.analyze # populates masses; process() alone leaves them empty
  mass = flay.masses.values.sum
  [mass <= FLAY_MAX, "duplication mass #{mass} (max #{FLAY_MAX})"]
end

GATES = { tests: -> { gate_tests }, rubocop: -> { gate_rubocop },
          flog: -> { gate_flog }, flay: -> { gate_flay } }.freeze

puts "quality gate:"
failures = []
GATES.each do |name, gate|
  ok, detail = gate.call
  failures << name unless ok
  puts format("  %<mark>s %<name>-8s %<detail>s", mark: ok ? "✓" : "✗", name: name, detail: detail)
end

if failures.empty?
  puts "→ PASS"
  exit 0
else
  puts "→ FAIL (#{failures.join(', ')})"
  exit 1
end
