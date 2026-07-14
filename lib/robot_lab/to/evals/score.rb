# frozen_string_literal: true

module RobotLab
  module To
    module Evals
      # The verdict an Eval returns for one iteration.
      #
      #   gate_ok    - floor holds? (correctness) -- must be true to commit
      #   improved   - better than the parent commit? (the descent signal)
      #   met_target - objective reached? (orchestrator-owned stop)
      #   value      - the score (higher = better); nil for pure-pairwise evals
      #   detail     - one-line human summary for logs / progress
      #   output     - diagnostic text (gate command output, judge rationale) used
      #                for repair prompts and notes; nil when there is none
      Score = Data.define(:gate_ok, :improved, :met_target, :value, :detail, :output) do
        def gate_ok?    = gate_ok
        def improved?   = improved
        def met_target? = met_target
      end
    end
  end
end
