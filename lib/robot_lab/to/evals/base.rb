# frozen_string_literal: true

module RobotLab
  module To
    module Evals
      # Base class for an Eval strategy. An Eval scores the uncommitted working
      # tree against a spec and returns a Score. It is the deciding authority for
      # commit/rollback (via gate_ok/improved) and stop (via met_target) -- not
      # the robot's self-report.
      #
      # Subclasses override #score. #protected_paths lists grader artifacts the
      # robot must not edit (wired into GraderLock in a later phase); the default
      # is none.
      class Base
        def score(context)
          raise NotImplementedError, "#{self.class}#score must return an Evals::Score"
        end

        def protected_paths = []
      end
    end
  end
end
