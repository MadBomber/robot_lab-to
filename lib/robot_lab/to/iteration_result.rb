# frozen_string_literal: true

module RobotLab
  module To
    IterationResult = Data.define(
      :success,           # Boolean
      :summary,           # String
      :key_changes,       # Array<String>
      :key_learnings,     # Array<String>
      :should_fully_stop  # Boolean or nil (nil when --stop-when not active)
    ) do
      def success? = success
      def stop?    = !!should_fully_stop

      # Used when --stop-when is not configured
      def self.no_stop_when(success:, summary:, key_changes: [], key_learnings: [])
        new(success: success, summary: summary,
            key_changes: key_changes, key_learnings: key_learnings,
            should_fully_stop: nil)
      end

      # Sentinel result when the robot returns without calling submit_iteration_result
      def self.not_submitted
        new(success: false, summary: "Robot did not call submit_iteration_result",
            key_changes: [], key_learnings: [], should_fully_stop: nil)
      end
    end
  end
end
