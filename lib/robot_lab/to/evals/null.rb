# frozen_string_literal: true

module RobotLab
  module To
    module Evals
      # The default Eval when nothing is configured: no gate, every reported
      # success counts as progress, no measurable target. Preserves robot_lab-to's
      # original "commit any claimed success; stop via --stop-when" behavior.
      class Null < Base
        def score(_context)
          Score.new(gate_ok: true, improved: true, met_target: false,
                    value: nil, detail: "no eval configured", output: nil)
        end
      end
    end
  end
end
