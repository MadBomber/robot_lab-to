#!/usr/bin/env ruby
# frozen_string_literal: true
#
# ===========================================================================
# 03_scored — drive robot_lab-to with an EVAL (measured descent)
# ===========================================================================
#
# 01_basic_usage uses a verify command: a change commits if the test suite exits
# 0 — pure pass/fail. This example instead scores each iteration with an **eval**
# and makes the loop *descend* toward a target.
#
# The metric is the number of PASSING test methods. A small grader script
# (score.rb) runs the seeded Roman-numeral suite and prints that count; higher is
# better. The orchestrator commits an iteration ONLY if it raises the count, rolls
# back anything that doesn't, and stops once every test passes (the target). Each
# iteration's prompt gets a "Score Feedback" section — "Best score so far: 6/9" —
# so the robot's next attempt is aimed, not blind.
#
# The grader (score.rb) and the test file are LOCKED with --protect-path: the
# GraderLock guard refuses any attempt by the robot to edit the criteria it is
# scored against, so it can't "win" by deleting a failing test.
#
# Everything stays under examples/03_scored/ (project/ and .robot_lab_to/), both
# git-ignored and wiped at the start of every run.
#
# ---------------------------------------------------------------------------
# Run it
# ---------------------------------------------------------------------------
#   # Local Ollama (default — no API key; requires `ollama serve`):
#   ollama pull gpt-oss:20b
#   bundle exec ruby examples/03_scored/scored_run.rb
#
#   # A cloud model instead:
#   RLTO_LOCAL=false RLTO_PROVIDER=anthropic RLTO_MODEL=claude-sonnet-4-6 \
#     ANTHROPIC_API_KEY=sk-... \
#     bundle exec ruby examples/03_scored/scored_run.rb
#
# Configuration (all optional, via environment):
#   RLTO_LOCAL     true|false   use a local Ollama model (default true)
#   RLTO_PROVIDER  name         LLM provider (default: openai for local)
#   RLTO_MODEL     id           model id (default: qwen3.6:latest for local)
#   OLLAMA_BASE    url          Ollama OpenAI endpoint (default localhost:11434/v1)
# ===========================================================================

require "fileutils"
require "logger"
require "open3"
require "net/http"

# Make the example runnable straight from the repo during development, with or
# without `bundle exec`. (When the gem is installed normally these paths don't
# exist and are skipped.)
[
  File.expand_path("../../lib", __dir__),           # robot_lab-to/lib
  File.expand_path("../../../robot_lab/lib", __dir__) # sibling robot_lab/lib
].each { |p| $LOAD_PATH.unshift(p) if Dir.exist?(p) }

require "ruby_llm"
require "robot_lab"
require "robot_lab/to"

# --- configuration ---------------------------------------------------------

LOCAL    = ENV.fetch("RLTO_LOCAL", "true") == "true"
PROVIDER = ENV.fetch("RLTO_PROVIDER", LOCAL ? "openai" : "anthropic").to_sym
MODEL    = ENV.fetch("RLTO_MODEL", LOCAL ? "qwen3.6:latest" : "claude-sonnet-4-6")
OLLAMA   = ENV.fetch("OLLAMA_BASE", "http://localhost:11434/v1")

TOTAL_TESTS = 9 # the seeded suite has 9 test methods — the target

# Route RubyLLM's :openai provider at Ollama's OpenAI-compatible endpoint for a
# local run (non-streaming, since Ollama suppresses tool calls when streaming).
def configure_local!
  RubyLLM.configure do |c|
    c.openai_api_base = OLLAMA
    c.openai_api_key  = "ollama"
    c.request_timeout = 600
  end
  RubyLLM.logger.level = Logger::ERROR
  RubyLLM.models.refresh!
rescue StandardError => e
  warn "warning: could not refresh Ollama models (#{e.class}: #{e.message})"
end

def preflight_local!
  uri = URI.join(OLLAMA, "models")
  Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 2) { |h| h.get(uri.request_uri) }
rescue StandardError
  abort <<~MSG
    Cannot reach an Ollama server at #{OLLAMA}.
    Start it and pull a tool-capable model first:

      ollama serve &
      ollama pull #{MODEL}

    Or run against a cloud model:
      RLTO_LOCAL=false RLTO_PROVIDER=anthropic RLTO_MODEL=claude-sonnet-4-6 \\
        ANTHROPIC_API_KEY=sk-... ruby #{File.basename(__FILE__)}
  MSG
end

# --- sandbox repository ----------------------------------------------------

def sh(*args, chdir:)
  out, err, status = Open3.capture3(*args, chdir: chdir)
  raise "command failed: #{args.join(' ')}\n#{err}" unless status.success?

  out
end

SANDBOX_DIR = File.expand_path("project", __dir__)
RUN_DIR     = File.expand_path(".robot_lab_to", __dir__)
ARTIFACTS   = [SANDBOX_DIR, RUN_DIR].freeze

def clean_slate!
  ARTIFACTS.each do |path|
    next unless File.exist?(path)

    puts "Cleaning leftover: #{path}"
    FileUtils.rm_rf(path)
  end
end

# The fixed, *failing* Minitest suite the robot must satisfy (9 test methods).
# Seeded into the sandbox and locked, so the robot can't game its own success.
ROMAN_TEST = <<~'RUBY'
  # frozen_string_literal: true

  require "minitest/autorun"
  require "roman_numeral"

  class RomanNumeralTest < Minitest::Test
    def test_to_roman_basic_digits
      assert_equal "I",   RomanNumeral.to_roman(1)
      assert_equal "III", RomanNumeral.to_roman(3)
      assert_equal "XII", RomanNumeral.to_roman(12)
    end

    def test_to_roman_subtractive_pairs
      { 4 => "IV", 9 => "IX", 40 => "XL", 90 => "XC", 400 => "CD", 900 => "CM" }.each do |n, roman|
        assert_equal roman, RomanNumeral.to_roman(n)
      end
    end

    def test_to_roman_composite_values
      assert_equal "MMXXIV", RomanNumeral.to_roman(2024)
      assert_equal "MCMLIV", RomanNumeral.to_roman(1954)
    end

    def test_to_roman_boundaries
      assert_equal "I",         RomanNumeral.to_roman(1)
      assert_equal "MMMCMXCIX", RomanNumeral.to_roman(3999)
    end

    def test_from_roman_round_trips_to_roman
      (1..3999).step(7) { |n| assert_equal n, RomanNumeral.from_roman(RomanNumeral.to_roman(n)) }
    end

    def test_from_roman_is_case_insensitive
      assert_equal 14, RomanNumeral.from_roman("xiv")
    end

    def test_to_roman_rejects_out_of_range
      assert_raises(ArgumentError) { RomanNumeral.to_roman(0) }
      assert_raises(ArgumentError) { RomanNumeral.to_roman(4000) }
    end

    def test_to_roman_rejects_non_integers
      assert_raises(ArgumentError) { RomanNumeral.to_roman("12") }
      assert_raises(ArgumentError) { RomanNumeral.to_roman(3.5) }
    end

    def test_from_roman_rejects_non_canonical_or_invalid
      ["IIII", "VV", "ABC", ""].each { |bad| assert_raises(ArgumentError) { RomanNumeral.from_roman(bad) } }
    end
  end
RUBY

# The GRADER: prints the number of passing test methods (higher = better). Wired
# as --measure and locked with --protect-path so the robot can't edit the metric.
# When the library is missing, the suite fails to load and this prints 0.
SCORE_SCRIPT = <<~'RUBY'
  #!/usr/bin/env ruby
  # frozen_string_literal: true
  out = `ruby -Ilib -Itest test/roman_numeral_test.rb 2>&1`
  m = out.match(/(\d+)\s+runs?,.*?(\d+)\s+failures?,\s*(\d+)\s+errors?/m)
  puts(m ? (m[1].to_i - m[2].to_i - m[3].to_i) : 0)
RUBY

def make_sandbox
  FileUtils.mkdir_p(File.join(SANDBOX_DIR, "test"))
  sh("git", "init", "-q", chdir: SANDBOX_DIR)
  sh("git", "config", "user.email", "example@example.com", chdir: SANDBOX_DIR)
  sh("git", "config", "user.name", "robot_lab-to example", chdir: SANDBOX_DIR)

  File.write(File.join(SANDBOX_DIR, "test", "roman_numeral_test.rb"), ROMAN_TEST)
  File.write(File.join(SANDBOX_DIR, "score.rb"), SCORE_SCRIPT)
  File.write(File.join(SANDBOX_DIR, "README.md"),
             "# Roman numeral kata (scored)\n\n" \
             "Implement `lib/roman_numeral.rb` to make more of the suite pass.\n" \
             "Score = passing test methods (grader: `ruby score.rb`). Target #{TOTAL_TESTS}.\n")

  sh("git", "add", "-A", chdir: SANDBOX_DIR)
  sh("git", "commit", "-qm", "initial: failing suite + grader", chdir: SANDBOX_DIR)
  SANDBOX_DIR
end

# --- live feedback (robot_lab hook) ----------------------------------------

# Narrates each robot action so a run never sits silent. See 01_basic_usage for a
# fuller writeup of the hook system.
class FeedbackHook < RobotLab::Hook
  class << self
    def before_llm_generation(_ctx)
      say "🤔 thinking…"
    rescue StandardError
      nil
    end

    def before_tool_call(ctx)
      icon, detail = describe(ctx.tool_name.to_s, ctx.tool_args || {})
      say "#{icon} #{detail}"
    rescue StandardError
      nil
    end

    private

    def say(message)
      $stderr.puts "      #{message}"
    end

    def describe(name, args)
      path = args["path"] || args[:path]
      case name
      when "read"  then ["📖", "read #{tidy(path)}"]
      when "write" then ["📝", "write #{tidy(path)}"]
      when "edit"  then ["✏️ ", "edit #{tidy(path)}"]
      when "bash"  then ["💻", "bash: #{snippet(args['command'] || args[:command])}"]
      when /submit_result/ then ["✅", "submit: #{snippet(args['summary'] || args[:summary], 160)}"]
      else ["🔧", name]
      end
    end

    def tidy(text)
      text.to_s.gsub("#{Dir.pwd}/", "").gsub(Dir.home, "~")
    end

    def snippet(text, limit = 90)
      line = tidy(text.to_s.lines.first.to_s.strip)
      line.length > limit ? "#{line[0, limit]}…" : line
    end
  end
end

# --- report ----------------------------------------------------------------

def final_score(dir)
  out, = Open3.capture2e("ruby", "score.rb", chdir: dir)
  out.strip
end

def report(dir)
  puts "\n=== Result ==="
  puts "Branch:  #{sh('git', 'branch', '--show-current', chdir: dir).strip}"
  puts "Score:   #{final_score(dir)}/#{TOTAL_TESTS} tests passing"
  puts "\nCommits (one per improvement):"
  puts sh("git", "log", "--oneline", chdir: dir)

  notes = Dir.glob(File.join(RUN_DIR, "runs", "*", "notes.md")).max
  puts "\nNotes:    #{notes}" if notes
  puts "Project:  #{dir}"
end

# --- main ------------------------------------------------------------------

OBJECTIVE = <<~OBJ.strip
  Implement a Roman numeral library in lib/roman_numeral.rb so that MORE of the
  Minitest suite in test/roman_numeral_test.rb passes each iteration.

  The module RomanNumeral must provide:
    1. RomanNumeral.to_roman(integer) -> String  (range 1..3999, subtractive
       notation; raises ArgumentError for non-Integers and out-of-range values)
    2. RomanNumeral.from_roman(string) -> Integer  (inverse of to_roman, case
       insensitive; raises ArgumentError for non-canonical strings)

  Your score is the number of passing test methods (run `ruby score.rb`). Make
  incremental progress — one focused change per iteration that raises the score.
  You may NOT edit test/roman_numeral_test.rb or score.rb (they are locked).
  Call submit_result each iteration describing what you improved.
OBJ

if LOCAL
  preflight_local!
  configure_local!
end

clean_slate!
sandbox = make_sandbox
puts "Project dir:     #{sandbox}"
puts "Provider/model:  #{PROVIDER}/#{MODEL} (#{LOCAL ? 'local Ollama' : 'cloud'})"
puts "Eval:            measured descent — score = passing tests, target #{TOTAL_TESTS}"
puts "Locked grader:   score.rb, test/roman_numeral_test.rb"
puts

RobotLab.on(FeedbackHook)

Dir.chdir(sandbox) do
  RobotLab::To.run(
    OBJECTIVE,
    provider:       PROVIDER,
    model:          MODEL,
    local_guards:   LOCAL,
    stream:         !LOCAL,
    max_iterations: 12,
    run_dir:        RUN_DIR,
    # The eval: commit only when the passing-test count RISES; stop at the target.
    eval_measure:   "ruby score.rb",
    eval_target:    TOTAL_TESTS.to_f,
    # Lock the grader + the test file so the robot can't game the metric.
    protect_paths:  ["score.rb", "test/roman_numeral_test.rb"]
  )
end

report(sandbox)
