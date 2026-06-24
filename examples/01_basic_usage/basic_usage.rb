#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Basic Usage would generally be as a CLI tool; however, its a library
# so that means you can build it inot an application program.
#
# ===========================================================================
# 01_basic_usage — drive robot_lab-to programmatically
# ===========================================================================
#
# This example shows an end-to-end use of the takeover library: it spins up a
# *throwaway* git repository seeded with a failing test suite, runs an autonomous
# loop against it with `RobotLab::To.run`, and prints what the robot produced.
#
# The objective is a small spec-driven kata: implement a Roman-numeral library
# (lib/roman_numeral.rb) until a fixed Minitest suite passes. The suite is seeded
# into the sandbox, so the robot must satisfy real, externally-defined tests it
# can't game. This exercises the full loop over several iterations: branch,
# iterate, verify (run the tests), commit on green / roll back on red.
#
# It also demonstrates the robot_lab HOOK system (see FeedbackHook below): a
# globally-registered hook narrates each robot action — thinking, reading,
# writing, running tests — so a run never sits silent while the model works.
#
# Nothing here touches your own repositories. Everything for this example stays
# under examples/01_basic_usage/:
#   * project/   — a fresh git repo the robot works in
#   * .robot_lab_to/     — the run's event log and cross-iteration notes.md
# Both are deleted at the start of every run for a clean slate, and are
# git-ignored, so they never become part of the robot_lab-to repo.
#
# ---------------------------------------------------------------------------
# Run it
# ---------------------------------------------------------------------------
#   # Local Ollama (default — no API key needed; requires `ollama serve`):
#   ollama pull gpt-oss:20b
#   bundle exec ruby examples/01_basic_usage/basic_usage.rb
#
#   # A cloud model instead:
#   RLTO_LOCAL=false RLTO_PROVIDER=anthropic RLTO_MODEL=claude-sonnet-4-6 \
#     ANTHROPIC_API_KEY=sk-... \
#     bundle exec ruby examples/01_basic_usage/basic_usage.rb
#
# Configuration (all optional, via environment):
#   RLTO_LOCAL     true|false   use a local Ollama model (default true)
#   RLTO_PROVIDER  name         LLM provider (default: openai for local)
#   RLTO_MODEL     id           model id (default: gpt-oss:20b for local)
#   OLLAMA_BASE    url          Ollama OpenAI endpoint (default localhost:11434/v1)
# ===========================================================================

require "fileutils"
require "logger"
require "open3"
require "net/http"

# Make the example runnable straight from the repo during development, with or
# without `bundle exec`. (When the gem is installed normally, these paths simply
# don't exist and are skipped.)
[
  File.expand_path("../../lib", __dir__),          # robot_lab-to/lib
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

# For a local model we route RubyLLM's :openai provider at Ollama's
# OpenAI-compatible endpoint, refresh the registry so tool attachment works, and
# run non-streaming (Ollama suppresses tool calls when streaming). See the
# "Local Models" guide in the docs for why.
def configure_local!
  RubyLLM.configure do |c|
    c.openai_api_base = OLLAMA
    c.openai_api_key  = "ollama" # ignored by Ollama, but RubyLLM wants a value
    c.request_timeout = 600
  end
  RubyLLM.logger.level = Logger::ERROR
  RubyLLM.models.refresh!
rescue StandardError => e
  warn "warning: could not refresh Ollama models (#{e.class}: #{e.message})"
end

# Fail fast with a friendly message if a local run can't reach Ollama.
def preflight_local!
  uri = URI.join(OLLAMA, "models")
  Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 2) do |http|
    http.get(uri.request_uri)
  end
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

# The sandbox project, created next to this script and git-ignored.
SANDBOX_DIR = File.expand_path("project", __dir__)

# Run state (event log + cross-iteration notes.md) is kept beside this example —
# under examples/01_basic_usage/.robot_lab_to — rather than at the repo root or
# buried inside project, so everything for the example stays in one
# place. It is git-ignored by the repo's .gitignore (`.robot_lab_to/`).
RUN_DIR = File.expand_path(".robot_lab_to", __dir__)

# Everything this example creates. Removed up front so each run starts clean.
ARTIFACTS = [SANDBOX_DIR, RUN_DIR].freeze

# Delete any leftovers from a previous execution so the app operates on a clean
# slate. Only the two paths this example creates are ever touched.
def clean_slate!
  ARTIFACTS.each do |path|
    next unless File.exist?(path)

    puts "Cleaning leftover: #{path}"
    FileUtils.rm_rf(path)
  end
end

# The fixed specification the robot must satisfy: a comprehensive, *failing*
# Minitest suite for a Roman-numeral library. Seeded into the sandbox so the
# robot can't game its own success — it has to make this exact suite pass.
# (`<<~'RUBY'` is non-interpolating, so the body is copied verbatim.)
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
      (1..3999).step(7) do |n|
        assert_equal n, RomanNumeral.from_roman(RomanNumeral.to_roman(n))
      end
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
      ["IIII", "VV", "ABC", ""].each do |bad|
        assert_raises(ArgumentError) { RomanNumeral.from_roman(bad) }
      end
    end
  end
RUBY

# Create a fresh git repo seeded with the failing test suite and one commit
# (robot-to needs a HEAD to branch from). Assumes clean_slate! has already run.
def make_sandbox
  FileUtils.mkdir_p(SANDBOX_DIR)
  sh("git", "init", "-q", chdir: SANDBOX_DIR)
  sh("git", "config", "user.email", "example@example.com", chdir: SANDBOX_DIR)
  sh("git", "config", "user.name", "robot_lab-to example", chdir: SANDBOX_DIR)

  FileUtils.mkdir_p(File.join(SANDBOX_DIR, "test"))
  File.write(File.join(SANDBOX_DIR, "test", "roman_numeral_test.rb"), ROMAN_TEST)
  File.write(File.join(SANDBOX_DIR, "README.md"),
             "# Roman numeral kata\n\n" \
             "Implement `lib/roman_numeral.rb` so that `test/roman_numeral_test.rb` passes.\n")

  sh("git", "add", "-A", chdir: SANDBOX_DIR)
  sh("git", "commit", "-qm", "initial: failing roman-numeral test suite", chdir: SANDBOX_DIR)
  SANDBOX_DIR
end

# --- live feedback (robot_lab hook) -----------------------------------------

# A RobotLab::Hook that narrates what the robot is doing in real time, so a run
# never sits silent while the model works. robot_lab fires these class methods
# around every robot run and tool call; registering the hook GLOBALLY with
# RobotLab.on (below) makes it apply to each per-iteration robot the orchestrator
# builds — no need to touch the orchestrator itself.
#
# Hook methods must never raise (an exception would abort the iteration), so each
# is wrapped defensively.
class FeedbackHook < RobotLab::Hook
  class << self
    # Fires once when a robot starts generating — the long "thinking" gap.
    def before_llm_generation(_ctx)
      say "🤔 thinking…"
    rescue StandardError
      nil
    end

    # Fires just before each tool runs — the robot's concrete actions.
    def before_tool_call(ctx)
      icon, detail = describe(ctx.tool_name.to_s, ctx.tool_args || {})
      say "#{icon} #{detail}"
    rescue StandardError
      nil
    end

    # Fires after each tool — surface errors and shell exit codes.
    def after_tool_call(ctx)
      if ctx.tool_error
        say "   ✗ #{snippet(ctx.tool_error.message)}"
      elsif ctx.tool_name.to_s == "bash" && (code = ctx.tool_result.to_s[/\[exit (\d+)\]/, 1])
        say "   ↳ exit #{code}"
      end
    rescue StandardError
      nil
    end

    private

    # Write to stderr directly (not Kernel#warn — that is a no-op when warnings
    # are disabled, i.e. $VERBOSE is nil, which is common under `bundle exec`).
    # $stderr is unbuffered, so feedback shows up live as the robot works.
    def say(message)
      $stderr.puts "      #{message}"
    end

    # Map a tool call to an icon + one-line description.
    def describe(name, args)
      path = args["path"] || args[:path]
      case name
      when "read"  then ["📖", "read #{tidy(path)}"]
      when "write" then ["📝", "write #{tidy(path)}"]
      when "edit"  then ["✏️ ", "edit #{tidy(path)}"]
      when "bash"  then ["💻", "bash: #{snippet(args['command'] || args[:command])}"]
      when /submit_result/ then ["✅", "submit result: #{snippet(args['summary'] || args[:summary], 160)}"]
      else ["🔧", name]
      end
    end

    # Shorten paths for display anywhere they appear: drop the project dir and
    # collapse $HOME to ~ (covers bare paths and embedded ones like `cd <path>`).
    def tidy(text)
      text.to_s.gsub("#{Dir.pwd}/", "").gsub(Dir.home, "~")
    end

    # First line of free text, paths tidied, capped with an ellipsis.
    def snippet(text, limit = 90)
      line = tidy(text.to_s.lines.first.to_s.strip)
      line.length > limit ? "#{line[0, limit]}…" : line
    end
  end
end

# --- report ----------------------------------------------------------------

def report(dir)
  puts "\n=== Result ==="
  puts "Branch:  #{sh('git', 'branch', '--show-current', chdir: dir).strip}"
  puts "\nCommits:"
  puts sh("git", "log", "--oneline", chdir: dir)

  impl = File.join(dir, "lib", "roman_numeral.rb")
  if File.exist?(impl)
    puts "\nlib/roman_numeral.rb:"
    puts File.read(impl)
  else
    puts "\n(lib/roman_numeral.rb was not created — check the notes for why)"
  end

  puts "\nFinal test run:"
  out, = Open3.capture2e("ruby", "-Ilib", "-Itest", "test/roman_numeral_test.rb", chdir: dir)
  summary = out.lines.grep(/runs?, |assertions|failures|Error/i).last(1).join.strip
  puts summary.empty? ? out.strip : summary

  notes = Dir.glob(File.join(RUN_DIR, "runs", "*", "notes.md")).max # newest run
  puts "\nNotes:    #{notes}" if notes
  puts "Project:  #{dir}"
  puts "Run logs: #{RUN_DIR}"
end

# --- main ------------------------------------------------------------------

OBJECTIVE = <<~OBJ.strip
  Implement a Roman numeral library in lib/roman_numeral.rb so that the existing
  Minitest suite in test/roman_numeral_test.rb passes with no failures or errors.

  The module RomanNumeral must provide two class methods:

    1. RomanNumeral.to_roman(integer) -> String
       - supports the range 1..3999 using standard subtractive notation
         (4=IV, 9=IX, 40=XL, 90=XC, 400=CD, 900=CM); e.g. to_roman(2024) => "MMXXIV"
       - raises ArgumentError for non-Integers and for values outside 1..3999

    2. RomanNumeral.from_roman(string) -> Integer
       - the exact inverse of to_roman over 1..3999, accepting upper or lower case
       - raises ArgumentError for any string that is not a CANONICAL Roman numeral
         (e.g. "IIII", "VV", "ABC", and "" are all invalid)

  Read test/roman_numeral_test.rb for the exact expectations, then implement the
  library. Run the suite with:

      ruby -Ilib -Itest test/roman_numeral_test.rb

  Work incrementally, one focused change per iteration, and do NOT edit the test
  file. Call submit_result when the suite passes.
OBJ

if LOCAL
  preflight_local!
  configure_local!
end

clean_slate! # delete any project / .robot_lab_to left by a previous run
sandbox = make_sandbox
puts "Project dir:     #{sandbox}"
puts "Provider/model:  #{PROVIDER}/#{MODEL} (#{LOCAL ? 'local Ollama' : 'cloud'})"
puts "Objective:       implement lib/roman_numeral.rb to pass the test suite"
puts

# Register the narrator globally so it reports on every per-iteration robot.
RobotLab.on(FeedbackHook)

Dir.chdir(sandbox) do
  RobotLab::To.run(
    OBJECTIVE,
    provider:       PROVIDER,
    model:          MODEL,
    local_guards:   LOCAL,    # built-in file tools + small-model guardrails
    stream:         !LOCAL,   # local Ollama tool calls require non-streaming
    max_iterations: 6,        # a richer task needs room to iterate
    run_dir:        RUN_DIR,  # keep logs + notes under this example directory
    # The change only commits if the seeded test suite passes:
    verify_command: "ruby -Ilib -Itest test/roman_numeral_test.rb",
    # Stop early once the suite is green (the robot judges this after a success):
    stop_when:      "test/roman_numeral_test.rb passes with 0 failures and 0 errors"
  )
end

report(sandbox)
