#!/usr/bin/env ruby
# frozen_string_literal: true

# ===========================================================================
# 02_advanced_usage — a multi-phase workflow: a network of robots collaborates
# with the user to ideate and plan, then robot_lab-to autonomously implements
# the plan behind a real quality gate.
# ===========================================================================
#
# This composes the two robot_lab subsystems:
#
#   Phase 1  IDEATE   (robot_lab Network task, gpt-5.5, interactive)
#       An "Ideator" robot interviews YOU via the AskUser tool, turning a rough
#       idea into a concrete requirements brief.
#
#   Phase 2  PLAN     (robot_lab Network task, gpt-5.5)
#       A "Planner" robot reads the brief and writes a Minitest *acceptance
#       suite* into the project (test/). It does not implement anything. Its
#       reply is a one-paragraph implementation objective.
#
#   Phase 3  IMPLEMENT (robot_lab-to, local Ollama qwen3.6:latest)
#       robot_lab-to runs an autonomous loop that writes lib/ code until the
#       Planner's acceptance suite passes AND a quality gate is clean. The
#       verify command (quality_gate.rb) runs tests + rubocop + flog + flay, so
#       the robot must earn each commit on correctness AND quality.
#
# Models (per your request): reasoning on OpenAI gpt-5.5, building on local
# Ollama qwen3.6. Because both use RubyLLM's :openai provider but different
# endpoints (api.openai.com vs Ollama's /v1), and openai_api_base is global, we
# toggle it between the (sequential) phases.
#
# Everything stays under examples/02_advanced_usage/ (project/, .robot_lab_to/),
# both git-ignored and recreated on each run.
#
# Run it (from the gem root, with OPENAI_API_KEY set and Ollama serving qwen3.6):
#   bundle exec ruby examples/02_advanced_usage/advanced_usage.rb
# ===========================================================================

require "fileutils"
require "logger"
require "open3"
require "net/http"

# Make the example runnable straight from the repo, with or without bundler.
[
  File.expand_path("../../lib", __dir__),             # robot_lab-to/lib
  File.expand_path("../../../robot_lab/lib", __dir__) # sibling robot_lab/lib
].each { |p| $LOAD_PATH.unshift(p) if Dir.exist?(p) }

require "ruby_llm"
require "robot_lab"
require "robot_lab/to"

# --- configuration ---------------------------------------------------------

REASON_PROVIDER = ENV.fetch("RLTO_REASON_PROVIDER", "openai").to_sym
REASON_MODEL    = ENV.fetch("RLTO_REASON_MODEL", "gpt-5.5")        # real OpenAI
BUILD_PROVIDER  = ENV.fetch("RLTO_BUILD_PROVIDER", "openai").to_sym
BUILD_MODEL     = ENV.fetch("RLTO_BUILD_MODEL", "qwen3.6:latest")  # local Ollama
OLLAMA_BASE     = ENV.fetch("OLLAMA_BASE", "http://localhost:11434/v1")

SANDBOX_DIR = File.expand_path("project", __dir__)
RUN_DIR     = File.expand_path(".robot_lab_to", __dir__)
ARTIFACTS   = [SANDBOX_DIR, RUN_DIR].freeze

RUBOCOP_CONFIG = <<~YAML
  AllCops:
    NewCops: enable
    SuggestExtensions: false
    TargetRubyVersion: "3.2"
  Style/Documentation: { Enabled: false }
  Style/FrozenStringLiteralComment: { Enabled: false }
  Metrics: { Enabled: false }
  Naming/MethodParameterName: { MinNameLength: 1 }
YAML

# --- live feedback -----------------------------------------------------------
#
# Live narration of every robot's actions across all three phases now comes from
# robot_lab core (RobotLab::Narrator) — we just enable it in main, below. No
# hand-written hook needed: it registers globally (covering the network robots
# AND the implementation loop) and writes to $stderr. For richer per-tool output
# (icons, shell exit codes) you can subclass RobotLab::Narrator and override
# before_tool_call / after_tool_call.

# --- provider configuration (toggled per phase) ----------------------------

# Reasoning phases talk to the real OpenAI API.
def use_real_openai!
  RubyLLM.configure do |c|
    c.openai_api_base = nil # default → api.openai.com
    c.openai_api_key  = ENV.fetch("OPENAI_API_KEY")
    c.request_timeout = 600
  end
  RubyLLM.logger.level = Logger::ERROR # keep raw API traffic out of the feed
end

# Implementation phase routes the :openai provider at the local Ollama endpoint.
def use_ollama!
  RubyLLM.configure do |c|
    c.openai_api_base = OLLAMA_BASE
    c.openai_api_key  = "ollama" # ignored by Ollama
    c.request_timeout = 600
  end
  RubyLLM.logger.level = Logger::ERROR
  RubyLLM.models.refresh! # register local models so tool attachment works
rescue StandardError => e
  warn "warning: could not refresh Ollama models (#{e.class}: #{e.message})"
end

# --- preflight -------------------------------------------------------------

def preflight!
  abort "Set OPENAI_API_KEY (the ideation/planning phases use #{REASON_MODEL})." unless ENV["OPENAI_API_KEY"]

  uri = URI.join(OLLAMA_BASE, "models")
  Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 2) { |h| h.get(uri.request_uri) }
rescue StandardError
  abort "Cannot reach Ollama at #{OLLAMA_BASE}. Start it and `ollama pull #{BUILD_MODEL}`."
end

# --- sandbox ---------------------------------------------------------------

def sh(*args, chdir:)
  out, err, status = Open3.capture3(*args, chdir: chdir)
  raise "command failed: #{args.join(' ')}\n#{err}" unless status.success?

  out
end

def clean_slate!
  ARTIFACTS.each do |path|
    next unless File.exist?(path)

    puts "Cleaning leftover: #{path}"
    FileUtils.rm_rf(path)
  end
end

# Fresh git repo seeded with the quality gate + rubocop config (the implementer
# inherits these). The acceptance tests are added later, by the Planner.
def make_sandbox
  FileUtils.mkdir_p(SANDBOX_DIR)
  sh("git", "init", "-q", chdir: SANDBOX_DIR)
  sh("git", "config", "user.email", "example@example.com", chdir: SANDBOX_DIR)
  sh("git", "config", "user.name", "robot_lab-to example", chdir: SANDBOX_DIR)

  FileUtils.cp(File.join(__dir__, "quality_gate.rb"), File.join(SANDBOX_DIR, "quality_gate.rb"))
  File.write(File.join(SANDBOX_DIR, ".rubocop.yml"), RUBOCOP_CONFIG)
  File.write(File.join(SANDBOX_DIR, "README.md"),
             "# Demo project\n\nlib/ implementation must satisfy test/ and pass `ruby quality_gate.rb`.\n")
  FileUtils.mkdir_p(File.join(SANDBOX_DIR, "lib"))
  FileUtils.mkdir_p(File.join(SANDBOX_DIR, "test"))

  sh("git", "add", "-A", chdir: SANDBOX_DIR)
  sh("git", "commit", "-qm", "chore: quality gate + project skeleton", chdir: SANDBOX_DIR)
  SANDBOX_DIR
end

# --- the reasoning robots (Phase 1 + 2) ------------------------------------

IDEATOR_PROMPT = <<~PROMPT
  You are a product ideation partner. Through a short interview, turn the user's
  rough idea into a crisp requirements brief for a TINY single-file Ruby library
  (implementable in ~100 lines, no gems, no I/O, no network).

  Use the ask_user tool to:
    1. Ask what small Ruby library they would like to build.
    2. Ask 2-3 focused clarifying questions (core operations, key edge cases,
       error handling, naming).
  Keep scope deliberately small — steer the user toward something a junior dev
  could build in an afternoon.

  When done, reply with ONLY the requirements brief: the library name (snake_case),
  the module/class name, and 5-8 bullet points describing required behavior and
  edge cases. Do not write any code.
PROMPT

PLANNER_PROMPT = <<~PROMPT
  You are a planning engineer. You are given a requirements brief for a tiny Ruby
  library. Produce the SPECIFICATION as an executable test suite — do NOT
  implement the library.

  Using the write tool, create ONE file: test/<snake_name>_test.rb — a thorough
  Minitest suite (require "minitest/autorun" and require "<snake_name>"). It must
  pin down: the happy paths, the important edge cases, and the error behavior
  named in the brief. Assume the implementation will live at lib/<snake_name>.rb
  and define the module/class the tests reference. Write 6-12 focused test methods.
  Do NOT create any lib/ file. Do NOT implement anything.

  After writing the test file, reply with ONE paragraph: a precise implementation
  objective naming lib/<snake_name>.rb, the module/class, and the public methods
  to implement so that test/<snake_name>_test.rb passes.
PROMPT

def build_reasoning_robots
  ideator = RobotLab.build(
    name: "ideator", system_prompt: IDEATOR_PROMPT,
    provider: REASON_PROVIDER, model: REASON_MODEL,
    local_tools: [RobotLab::AskUser.new], max_tool_rounds: 20
  )
  planner = RobotLab.build(
    name: "planner", system_prompt: PLANNER_PROMPT,
    provider: REASON_PROVIDER, model: REASON_MODEL,
    local_tools: [RobotLab::To::Tools::Write.new, RobotLab::To::Tools::Read.new],
    max_tool_rounds: 20
  )
  [ideator, planner]
end

# --- report ----------------------------------------------------------------

def report(dir)
  puts "\n=== Result ==="
  puts "Branch:  #{sh('git', 'branch', '--show-current', chdir: dir).strip}"
  puts "\nCommits:"
  puts sh("git", "log", "--oneline", chdir: dir)

  impl = Dir[File.join(dir, "lib", "**", "*.rb")].first
  if impl
    puts "\n#{impl.sub("#{dir}/", '')}:"
    puts File.read(impl)
  else
    puts "\n(no lib/ implementation was produced — check the notes for why)"
  end

  puts "\nFinal quality gate:"
  out, = Open3.capture2e("ruby", "quality_gate.rb", chdir: dir)
  puts out.strip

  notes = Dir.glob(File.join(RUN_DIR, "runs", "*", "notes.md")).max
  puts "\nNotes:    #{notes}" if notes
  puts "Project:  #{dir}"
  puts "Run logs: #{RUN_DIR}"
end

# --- main ------------------------------------------------------------------

preflight!
clean_slate!
sandbox = make_sandbox
RobotLab::Narrator.enable! # live narration for every robot, across all phases

puts "Project dir:  #{sandbox}"
puts "Reasoning:    #{REASON_PROVIDER}/#{REASON_MODEL} (cloud)   →  ideate + plan"
puts "Building:     #{BUILD_PROVIDER}/#{BUILD_MODEL} (local Ollama)  →  implement"
puts

# -- Phases 1 & 2: ideate -> plan, as a robot_lab network --------------------
puts "── Phase 1+2: ideation & planning (a network of robots) ──"
use_real_openai!
ideator, planner = build_reasoning_robots

network = RobotLab.create_network(name: "ideate_and_plan") do
  task :ideate, ideator, depends_on: :none
  task :plan,   planner, depends_on: [:ideate]
end

# Run inside the sandbox so the Planner's `write` lands in project/test/.
result = Dir.chdir(sandbox) do
  network.run(message: "Begin the ideation interview with the user.")
end

# The Planner-authored tests ARE the spec, so we derive the implementation
# objective from them. The Planner's prose reply is appended as a hint —
# robot_lab core now backfills last_text_content from the chat when a turn ends
# on a tool call, so it's reliably populated rather than blank.
test_files = Dir[File.join(sandbox, "test", "**", "*_test.rb")].map { |f| f.sub("#{sandbox}/", "") }
if test_files.empty?
  abort "Planning did not produce a test suite; aborting before implementation."
end

plan_notes = result.context[:plan]&.last_text_content.to_s.strip
objective = +<<~OBJ
  Implement the Ruby library so the acceptance test suite passes AND the quality
  gate is clean. The acceptance tests (do NOT edit them) are: #{test_files.join(', ')}.
  Read those tests to learn the required module/class, methods, and edge cases,
  create the matching lib/*.rb file(s) they require, and iterate until
  `ruby quality_gate.rb` exits 0 — it runs the tests plus rubocop, flog (method
  complexity), and flay (duplication) on lib/. Keep the code clean and simple.
OBJ
objective << "\nPlanner's notes: #{plan_notes}\n" unless plan_notes.empty?

# Commit the Planner-authored acceptance suite as the spec baseline.
sh("git", "add", "-A", chdir: sandbox)
sh("git", "commit", "-qm", "spec: acceptance tests from planning", chdir: sandbox)
puts "\nPlanning complete. Acceptance suite: #{test_files.join(', ')}"
puts "Objective derived from the spec.\n\n"

# -- Phase 3: autonomous implementation with robot_lab-to --------------------
puts "── Phase 3: implementation (robot_lab-to, quality-gated) ──"
use_ollama!

Dir.chdir(sandbox) do
  RobotLab::To.run(
    objective,
    provider:       BUILD_PROVIDER,
    model:          BUILD_MODEL,
    local_guards:   true,   # built-in file tools + small-model guardrails
    stream:         false,  # Ollama tool calls require non-streaming
    max_iterations: 8,
    run_dir:        RUN_DIR,
    verify_command: "ruby quality_gate.rb", # tests + rubocop + flog + flay
    stop_when:      "ruby quality_gate.rb passes with exit status 0"
  )
end

report(sandbox)
