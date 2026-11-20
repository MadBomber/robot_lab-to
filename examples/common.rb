# frozen_string_literal: true
#
# ===========================================================================
# common.rb — shared RubyLLM setup/teardown for the robot_lab-to example demos
# ===========================================================================
#
# Every example under examples/ requires this file (examples/.envrc supplies
# the RLTO_* / LMS_BASE_URL defaults) and calls `setup` before talking to
# RubyLLM -- once for a single-model example, or once per model role for an
# example with more than one (e.g. 04_prose's doer + judge).
#
#   actual_provider = setup(provider: PROVIDER, model: MODEL)
#   RobotLab::To.run(objective, provider: actual_provider, model: MODEL, ...)
#
# "lms" is the ruby_llm-providers-lms gem's native LM Studio provider.
# When `provider` is "lms", setup:
#   1. points the :lms provider at LMS_BASE_URL
#   2. starts the LM Studio server if it isn't already running
#   3. loads `model` into LM Studio if it isn't already loaded
# and returns :lms -- the RubyLLM-recognized provider to pass to RobotLab.
# Any other provider (a cloud one) passes straight through untouched; setup
# does nothing else for it (the example configures its own API key as before).
#
# teardown stops the LM Studio server, but ONLY if setup started it here -- a
# server you already had running (the LM Studio app, another example) is left
# alone. It runs automatically via an at_exit hook; examples never call it.
# ===========================================================================

require "json"
require "logger"
require "open3"
require "uri"

require "ruby_llm"
require "ruby_llm/providers/lms"

LMS_BASE_URL = ENV.fetch("LMS_BASE_URL", "http://localhost:1234/v1")

@lms_server_started_by_us = false

def setup(provider: ENV.fetch("RLTO_PROVIDER", "lms"), model: ENV.fetch("RLTO_MODEL", "qwen/qwen3.8-27b"))
  provider = provider.to_sym
  return provider unless provider == :lms

  configure_lms!
  ensure_lms_server_running!
  ensure_lms_model_loaded!(model)
  :lms
end

def teardown
  return unless @lms_server_started_by_us

  puts "Stopping the LM Studio server (started for this run)…"
  Open3.capture2e("lms", "server", "stop")
end

at_exit { teardown }

# --- internals ---------------------------------------------------------------

# Point the :lms provider at the LM Studio endpoint. Local models are assumed
# to exist, so no registry refresh is needed.
def configure_lms!
  RubyLLM.configure do |c|
    c.lms_api_base    = LMS_BASE_URL
    c.request_timeout = 600
  end
  RubyLLM.logger.level = Logger::ERROR
end

def lms_server_running?
  out, status = Open3.capture2("lms", "server", "status", "--json")
  status.success? && JSON.parse(out)["running"] == true
rescue StandardError
  false
end

def ensure_lms_server_running!
  return if lms_server_running?

  puts "Starting the LM Studio server…"
  port = URI.parse(LMS_BASE_URL).port.to_s
  out, status = Open3.capture2e("lms", "server", "start", "--port", port)
  abort "Could not start the LM Studio server:\n#{out}" unless status.success? && lms_server_running?

  @lms_server_started_by_us = true
rescue Errno::ENOENT
  abort "The `lms` CLI was not found. Install LM Studio (https://lmstudio.ai) and " \
        "run `lms bootstrap` to put it on your PATH."
end

def lms_model_loaded?(model)
  out, status = Open3.capture2("lms", "ps", "--json")
  return false unless status.success?

  JSON.parse(out).any? { |m| m["modelKey"] == model || m["identifier"] == model }
rescue StandardError
  false
end

def ensure_lms_model_loaded!(model)
  return if lms_model_loaded?(model)

  puts "Loading #{model} into LM Studio (first run only)…"
  out, status = Open3.capture2e("lms", "load", model, "-y")
  abort "Could not load #{model} in LM Studio:\n#{out}" unless status.success?
rescue Errno::ENOENT
  abort "The `lms` CLI was not found. Install LM Studio (https://lmstudio.ai) and " \
        "run `lms bootstrap` to put it on your PATH."
end
