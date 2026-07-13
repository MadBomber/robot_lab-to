# frozen_string_literal: true

module RobotLab
  module To
    module Evals
      # What the orchestrator hands an Eval each iteration. One value object so
      # new fields can be added without breaking custom evals.
      #
      #   work_dir       - the working tree holding the robot's uncommitted changes
      #   previous_ref   - git ref of the last committed state (HEAD before this iter)
      #   previous_value - last committed score value (nil until tracked; Phase 2)
      #   objective      - the run objective
      #   iteration      - 1-based iteration number
      Context = Data.define(:work_dir, :previous_ref, :previous_value, :objective, :iteration)
    end
  end
end
