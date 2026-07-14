# frozen_string_literal: true

require_relative "to/version"
require_relative "to/errors"
require_relative "to/iteration_result"
require_relative "to/run"
require_relative "to/atomic_file"
require_relative "to/jsonl_logger"
require_relative "to/notes_manager"
require_relative "to/decision"
require_relative "to/decision_manager"
require_relative "to/commit_manager"
require_relative "to/verifier"
require_relative "to/evals/score"
require_relative "to/evals/context"
require_relative "to/evals/base"
require_relative "to/evals/null"
require_relative "to/evals/code"
require_relative "to/evals/prose"
require_relative "to/evals/factory"
require_relative "to/config"
require_relative "to/tools/submit_result"
require_relative "to/tools/request_decision"
require_relative "to/tools/file_tool"
require_relative "to/tools/read"
require_relative "to/tools/write"
require_relative "to/tools/edit"
require_relative "to/tools/bash"
require_relative "to/guards"
require_relative "to/prompt_builder"
require_relative "to/backoff"
require_relative "to/stop_conditions"
require_relative "to/orchestrator"
require_relative "to/exit_summary"
require_relative "to/cli"

module RobotLab
  module To
    class << self
      # Launch an autonomous takeover run.
      #
      # @param objective [String] what the robot should work toward
      # @param opts [Hash] configuration overrides (model:, max_iterations:, etc.)
      # @return [void]
      def run(objective, **)
        config = Config.new(**)
        suppress_llm_logging unless config.debug?
        Orchestrator.new(objective, config).run
      end

      # Resume a paused run by id (used for cron/exit-mode operation). The
      # objective and prior state are loaded from the run's run.json.
      def resume(run_id, **)
        config = Config.new(**)
        suppress_llm_logging unless config.debug?
        Orchestrator.new(nil, config, resume_run_id: run_id).run
      end

      # Registry of named Eval strategies (see RobotLab::To::Evals.build). The
      # block receives the Config and returns an object responding to #score.
      def evals = (@evals ||= {})

      def register_eval(name, &block)
        evals[name.to_sym] = block
      end

      private

      def suppress_llm_logging
        require "logger"
        null = Logger.new(File::NULL)
        RubyLLM.configure { |c| c.logger = null } if defined?(RubyLLM)
        RobotLab.configure { |c| c.logger = null } if RobotLab.respond_to?(:configure)
      end
    end
  end
end

if defined?(RobotLab) && RobotLab.respond_to?(:register_extension)
  RobotLab.register_extension(:to, RobotLab::To)
end
