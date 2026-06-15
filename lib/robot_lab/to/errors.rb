# frozen_string_literal: true

module RobotLab
  module To
    class Error < StandardError; end

    # Unrecoverable condition (e.g. credit exhaustion). Aborts the run immediately.
    class PermanentError < Error; end

    # git commit failed. Preserves uncommitted changes so the next iteration can repair them.
    class CommitFailedError < Error
      attr_reader :output

      def initialize(msg, output: nil)
        super(msg)
        @output = output
      end
    end

    # A stop condition was triggered. Results in a clean exit (not an error).
    class AbortError < Error
      attr_reader :reason

      def initialize(reason)
        super
        @reason = reason
      end
    end
  end
end
