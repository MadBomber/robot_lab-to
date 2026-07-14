# frozen_string_literal: true

module RobotLab
  module To
    # Evaluates all stop conditions against the current run state.
    class StopConditions
      def initialize(config, run)
        @config = config
        @run    = run
      end

      # Checked before starting a new iteration.
      def before?
        check_max_iterations || check_max_tokens
      end

      # Checked after an iteration completes.
      def after?
        check_max_iterations || check_max_tokens || check_consecutive_failures || check_plateau
      end

      # Checked after a successful iteration with a stop_when condition.
      def stop_when_met?(result)
        return false unless @config.stop_when
        return false unless result.stop?

        raise AbortError, "stop condition met: #{@config.stop_when}"
      end

      # Called by the orchestrator's token-tracking callback mid-iteration.
      # Returns the abort reason string if exceeded, nil otherwise.
      def token_limit_exceeded?
        return false unless @config.max_tokens

        @run.total_tokens >= @config.max_tokens
      end

      private

      def check_max_iterations
        return unless @config.max_iterations
        return unless @run.iteration >= @config.max_iterations

        raise AbortError, "max iterations reached (#{@config.max_iterations})"
      end

      def check_max_tokens
        return unless @config.max_tokens
        return unless @run.total_tokens >= @config.max_tokens

        raise AbortError, "max tokens reached (#{@config.max_tokens})"
      end

      def check_consecutive_failures
        return unless @run.consecutive_failures >= @config.max_consecutive_failures

        raise AbortError, "#{@run.consecutive_failures} consecutive failures"
      end

      # Diminishing returns: stop after N iterations with no committed improvement.
      # The primary terminator for pairwise/judged evals, which never set a target.
      def check_plateau
        limit = @config.stop_on_plateau
        return unless limit
        return unless @run.iterations_since_improvement >= limit

        raise AbortError, "plateau: #{limit} iterations without improvement"
      end
    end
  end
end
