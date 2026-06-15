# frozen_string_literal: true

module RobotLab
  module To
    module Tools
      # Tool the robot MUST call as its final action to declare the iteration result.
      #
      # Create a fresh instance per iteration. After robot.run() returns, read
      # captured_result (nil if the robot never called the tool).
      class SubmitResult < RobotLab::Tool
        description <<~DESC
          Submit the result of this iteration. You MUST call this tool as your
          FINAL action before finishing. Do not call it until your work is complete.
        DESC

        param :success, type: "boolean",
                        desc: "true if you made meaningful progress toward the objective; " \
                              "false if you made no meaningful changes AND have no new learnings"

        param :summary, type: "string",
                        desc: "Brief one-sentence description of what you accomplished or why you stopped"

        param :key_changes, type: "array",
                            desc: "List of files or changes made this iteration (empty if none)",
                            required: false

        param :key_learnings, type: "array",
                              desc: "Insights worth remembering for future iterations (empty if none)",
                              required: false

        param :should_fully_stop, type: "boolean",
                                  desc: "Set to true only when instructed by a stop condition",
                                  required: false

        attr_reader :captured_result

        def execute(success:, summary:, key_changes: [], key_learnings: [], should_fully_stop: nil, **)
          @captured_result = IterationResult.new(
            success: success,
            summary: summary,
            key_changes: Array(key_changes),
            key_learnings: Array(key_learnings),
            should_fully_stop: should_fully_stop
          )
          "Iteration complete. Stop all work now."
        end
      end
    end
  end
end
