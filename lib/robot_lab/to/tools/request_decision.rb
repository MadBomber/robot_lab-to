# frozen_string_literal: true

module RobotLab
  module To
    module Tools
      # Tool the robot calls to escalate a choice it should NOT make on its own.
      #
      # Instead of blocking on a human (impossible in an unattended loop), the
      # robot records the decision as an artifact — situation, options, and its
      # recommended lean — and keeps going or stops. The orchestrator persists
      # each captured request as a decision file; a human resolves it out-of-band.
      #
      # Create a fresh instance per iteration. After robot.run() returns, read
      # captured_requests (empty if the robot raised none).
      class RequestDecision < RobotLab::Tool
        description <<~DESC
          Record a decision that requires HUMAN judgment and must not be made
          autonomously — an irreversible or hard-to-reverse choice, a public
          contract, an ambiguity about intent, or something outside the stated
          objective. Always include your recommended option (your "lean").

          This does NOT block for an answer. If blocking is true, the run pauses
          after this iteration until a human resolves the decision; if false,
          keep making progress on other work you can safely do. Do NOT use this
          for routine engineering choices you are equipped to make yourself.
        DESC

        parameter :question, type: "string",
                         description: "The decision that needs a human answer, phrased as a question"

        parameter :situation, type: "string",
                          description: "Why this needs a human and what is at stake", required: false

        parameter :options, type: "array",
                        description: "The distinct options you see (strings)", required: false

        parameter :recommendation, type: "string",
                               description: "Your recommended option and the reasoning behind it", required: false

        parameter :blocking, type: "boolean",
                         description: "true if work cannot correctly proceed until this is answered", required: false

        def captured_requests
          @captured_requests ||= []
        end

        # :reek:BooleanParameter :reek:ControlParameter -- blocking is both
        # stored data and legitimately changes the guidance message returned
        # to the robot; the `param` declarations above fix this signature.
        # :reek:LongParameterList -- one field per tool param declared above.
        def execute(question:, situation: "", options: [], recommendation: "", blocking: false, **)
          (@captured_requests ||= []) << {
            question: question,
            situation: situation.to_s,
            options: Array(options),
            recommendation: recommendation.to_s,
            blocking: blocking ? true : false
          }

          if blocking
            "Decision recorded (BLOCKING). Stop work now and call submit_iteration_result; " \
              "the run will pause until a human resolves it."
          else
            "Decision recorded. Continue with other work you can safely do, then submit your result."
          end
        end
      end
    end
  end
end
