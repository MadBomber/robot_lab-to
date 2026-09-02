#!/usr/bin/env ruby
# frozen_string_literal: true
#
# ===========================================================================
# 04_prose — two-phase authoring: outline (graded), then sections (graded)
# ===========================================================================
#
# A single pairwise loop can't reliably build a structured document with a small
# local model. This demo splits the work into two graded phases, each driven by a
# CUSTOM eval that asks a *separate* judge model for an ABSOLUTE verdict:
#
#   Phase 1 — OUTLINE:  the doer writes outline.md; the judge grades it READY or
#             NEEDS_WORK (with feedback). The run ends when the outline is READY.
#   Phase 2 — SECTIONS: for the approved outline, the doer writes one section per
#             iteration as its own file (sections/NN_*.md); the judge grades each
#             section. The run ends when every outline section has a READY file.
#   Finally the approved sections are assembled into guide.md.
#
# Two models, two roles (the same local model by default, but independently
# configurable — pass --judge-model / RLTO_JUDGE_MODEL for a stronger judge):
#   DOER     (default qwen/qwen3.8-27b) — writes the outline and the sections
#   VERIFIER (default qwen/qwen3.8-27b) — the judge; grades each artifact absolutely
#
# The judge writes its feedback to REVIEW.md (git-ignored in the sandbox); the
# doer is told to read REVIEW.md each iteration. write_guard is disabled for the
# doer so it can freely rewrite the file it is refining.
#
# ---------------------------------------------------------------------------
# Run it
# ---------------------------------------------------------------------------
#   bundle exec ruby examples/04_prose/prose_run.rb
#
# common.rb starts the LM Studio server and loads the doer + judge models for
# you if they aren't already running/loaded.
#
# Env: RLTO_MODEL (doer), RLTO_JUDGE_MODEL (verifier), RLTO_TOPIC, RLTO_LOCAL,
#      RLTO_PROVIDER, LMS_BASE_URL. (examples/.envrc sets these for you)
# ===========================================================================

require "fileutils"
require "open3"

[
  File.expand_path("../../lib", __dir__),
  File.expand_path("../../../robot_lab/lib", __dir__)
].each { |p| $LOAD_PATH.unshift(p) if Dir.exist?(p) }

# Load robot_lab prompt templates (the judge's system prompt) from this demo's
# prompts_dir via robot_lab's OWN config env var — no reaching into PromptManager.
# Set before robot_lab loads its config so RobotLab.build(template:) resolves here.
PROMPTS_DIR = File.expand_path("prompts_dir", __dir__)
ENV["ROBOT_LAB_TEMPLATE_PATH"] = PROMPTS_DIR

require "robot_lab"
require "robot_lab/to"
require_relative "../common"
RobotLab.reload_config! if RobotLab.respond_to?(:reload_config!)

# --- configuration ---------------------------------------------------------

LOCAL       = ENV.fetch("RLTO_LOCAL", "true") == "true"
PROVIDER    = ENV.fetch("RLTO_PROVIDER", LOCAL ? "lms" : "anthropic").to_sym
DOER_MODEL  = ENV.fetch("RLTO_MODEL", LOCAL ? "qwen/qwen3.8-27b" : "claude-sonnet-4-6")
JUDGE_MODEL = ENV.fetch("RLTO_JUDGE_MODEL", LOCAL ? "qwen/qwen3.8-27b" : "claude-sonnet-4-6")
TOPIC       = ENV.fetch("RLTO_TOPIC", "writing good Git commit messages")

# ruby_llm has no native "lms" adapter. "lms" is this example's friendly label for
# "a local LM Studio model"; setup (common.rb) resolves it to RubyLLM's :openai
# adapter pointed at LM Studio, starting the server and loading each model as
# needed -- once for the doer, again for the judge (a no-op if they're the same
# model, or if it's already loaded). Everything passed to RobotLab uses the
# resolved provider; PROVIDER itself is kept only for display.
LLM_PROVIDER = setup(provider: PROVIDER, model: DOER_MODEL)
setup(provider: PROVIDER, model: JUDGE_MODEL)

# --- the judge (absolute grader) -------------------------------------------

# Ask the judge model to grade `text` against `criteria`. The judge's system
# prompt is a robot_lab template (prompts_dir/judge.md).
# @return [Array(Boolean, String)] [ready?, feedback]
def grade(criteria, text)
  judge = RobotLab.build(name: "judge", model: JUDGE_MODEL, provider: LLM_PROVIDER, template: :judge)
  message = RobotLab.render_template(:grade_message, criteria: criteria, artifact: text)
  reply = judge.run(message).last_text_content.to_s
  ready = reply.match?(/\bREADY\b/i) && !reply.match?(/NEEDS_WORK/i)
  feedback = reply[/NEEDS_WORK:?\s*(.+)/im, 1].to_s.strip.slice(0, 400)
  [ready, feedback.empty? ? reply.strip.slice(0, 400) : feedback]
end

# The judge's feedback for the doer's next iteration. Written by the eval
# (orchestrator-side, so no WriteGuard); read by the doer. Git-ignored.
def write_review(dir, text)
  File.write(File.join(dir, "REVIEW.md"), "# Reviewer feedback (read me before revising)\n\n#{text}\n")
rescue StandardError
  nil
end

def pending_score(detail)
  RobotLab::To::Evals::Score.new(gate_ok: true, improved: false, met_target: false,
                                 value: nil, detail: detail, output: nil)
end

# --- Phase 1 eval: grade the outline ---------------------------------------

class OutlineGrader < RobotLab::To::Evals::Base
  def initialize(work_dir:)
    super()
    @work_dir = work_dir
  end

  def score(_context)
    outline = File.read(File.join(@work_dir, "outline.md")) rescue ""
    return pending_score("no outline yet") if outline.strip.empty?

    ready, feedback = grade(RobotLab.render_template(:outline_criteria, topic: TOPIC), outline)
    write_review(@work_dir, ready ? "The outline is approved. (Phase 2 will use it.)" : feedback)
    RobotLab::To::Evals::Score.new(
      gate_ok: true, improved: true, met_target: ready, value: nil,
      detail: ready ? "outline READY" : "NEEDS_WORK: #{feedback}", output: feedback
    )
  end
end

# --- Phase 2 eval: grade each section, finish when all are written ----------

class SectionGrader < RobotLab::To::Evals::Base
  def initialize(work_dir:, total:)
    super()
    @work_dir = work_dir
    @total    = total
  end

  def score(_context)
    files = section_files
    return pending_score("no sections yet") if files.empty?

    latest = files.last
    body   = File.read(latest) rescue ""
    ready, feedback = grade(RobotLab.render_template(:section_criteria, topic: TOPIC), body)
    done = files.size >= @total && ready
    write_review(@work_dir, section_note(files.size, ready, feedback))
    RobotLab::To::Evals::Score.new(
      gate_ok: true, improved: true, met_target: done, value: nil,
      detail: "sections #{files.size}/#{@total} latest=#{ready ? 'READY' : 'NEEDS_WORK'}",
      output: feedback
    )
  end

  private

  def section_files
    Dir.glob(File.join(@work_dir, "sections", "*.md")).sort
  end

  def section_note(count, ready, feedback)
    return "Section #{count}/#{@total} needs work: #{feedback}" unless ready
    return "Section #{count} looks good. Write the NEXT section (#{count + 1}/#{@total})." if count < @total

    "All #{@total} sections are written and approved."
  end
end

# --- live feedback (robot_lab hook) ----------------------------------------

class FeedbackHook < RobotLab::Hook
  class << self
    def before_llm_generation(_ctx)
      $stderr.puts "      🤔 thinking…"
    rescue StandardError
      nil
    end

    def before_tool_call(ctx)
      args = ctx.tool_args || {}
      target = tidy(args["path"] || args[:path] || args["command"] || args[:command])
      $stderr.puts "      🔧 #{ctx.tool_name}: #{target}"
    rescue StandardError
      nil
    end

    def tidy(text)
      text.to_s.lines.first.to_s.strip.gsub("#{Dir.pwd}/", "").slice(0, 90)
    end
  end
end

# --- sandbox ---------------------------------------------------------------

def sh(*args, chdir:)
  out, err, status = Open3.capture3(*args, chdir: chdir)
  raise "command failed: #{args.join(' ')}\n#{err}" unless status.success?

  out
end

SANDBOX_DIR = File.expand_path("project", __dir__)
RUN_DIR     = File.expand_path(".robot_lab_to", __dir__)

def clean_slate!
  [SANDBOX_DIR, RUN_DIR].each do |path|
    next unless File.exist?(path)

    puts "Cleaning leftover: #{path}"
    FileUtils.rm_rf(path)
  end
end

def make_sandbox
  FileUtils.mkdir_p(SANDBOX_DIR)
  sh("git", "init", "-q", chdir: SANDBOX_DIR)
  sh("git", "config", "user.email", "example@example.com", chdir: SANDBOX_DIR)
  sh("git", "config", "user.name", "robot_lab-to example", chdir: SANDBOX_DIR)
  File.write(File.join(SANDBOX_DIR, ".gitignore"), "REVIEW.md\n") # judge feedback, not part of the work
  File.write(File.join(SANDBOX_DIR, "README.md"), "# Prose demo\n\nBuilt in two graded phases; see the guide.\n")
  sh("git", "add", "-A", chdir: SANDBOX_DIR)
  sh("git", "commit", "-qm", "initial: empty sandbox", chdir: SANDBOX_DIR)
  SANDBOX_DIR
end

# Count the numbered items in the approved outline — the number of sections.
def outline_section_count(dir)
  File.read(File.join(dir, "outline.md")).scan(/^\s*\d+\.\s+\S/).size
rescue StandardError
  0
end

def assemble_guide(dir)
  sections = Dir.glob(File.join(dir, "sections", "*.md")).sort
  return if sections.empty?

  body = sections.map { |f| File.read(f).strip }.join("\n\n")
  File.write(File.join(dir, "guide.md"), "# An Opinionated Guide to #{TOPIC.capitalize}\n\n#{body}\n")
  sh("git", "add", "-A", chdir: dir)
  sh("git", "commit", "-qm", "assemble: guide.md from approved sections", chdir: dir)
end

# --- objectives ------------------------------------------------------------

OUTLINE_OBJECTIVE = RobotLab.render_template(:outline_objective, topic: TOPIC).strip

def sections_objective(total)
  RobotLab.render_template(:sections_objective, total: total).strip
end

# --- main ------------------------------------------------------------------

clean_slate!
sandbox = make_sandbox
puts "Project dir:     #{sandbox}"
puts "Doer model:      #{DOER_MODEL}"
puts "Verifier model:  #{JUDGE_MODEL}"
puts "Topic:           #{TOPIC}"
puts

RobotLab.on(FeedbackHook)

common = {
  provider: LLM_PROVIDER, model: DOER_MODEL, local_guards: LOCAL, stream: !LOCAL,
  run_dir: RUN_DIR, write_guard: false, require_improvement: false
}

Dir.chdir(sandbox) do
  puts "=== Phase 1: outline (graded until READY) ==="
  RobotLab::To.run(OUTLINE_OBJECTIVE, **common, max_iterations: 6,
                   eval: OutlineGrader.new(work_dir: sandbox))

  total = outline_section_count(sandbox)
  total = 5 if total.zero? # fall back if the outline wasn't a clean numbered list
  puts "\n=== Phase 2: #{total} sections (each graded) ==="
  RobotLab::To.run(sections_objective(total), **common, max_iterations: total * 3 + 2,
                   eval: SectionGrader.new(work_dir: sandbox, total: total))

  assemble_guide(sandbox)
end

# --- report ----------------------------------------------------------------

puts "\n=== Result ==="
puts "Commits:"; puts sh("git", "log", "--oneline", chdir: sandbox)
guide = File.join(sandbox, "guide.md")
if File.exist?(guide)
  puts "\nguide.md (#{File.read(guide).lines.size} lines):"
  puts File.read(guide)
else
  puts "\n(guide.md not assembled — check outline.md and sections/ in #{sandbox})"
end
