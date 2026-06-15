# frozen_string_literal: true

require_relative "to/version"
require_relative "to/errors"
require_relative "to/iteration_result"
require_relative "to/run"
require_relative "to/jsonl_logger"
require_relative "to/notes_manager"
require_relative "to/commit_manager"
require_relative "to/config"
require_relative "to/tools/submit_result"
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
