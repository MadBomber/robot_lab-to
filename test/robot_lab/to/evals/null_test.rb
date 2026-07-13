# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Evals
      class NullTest < Minitest::Test
        def test_reports_open_gate_and_progress_with_no_target
          score = Null.new.score(context)
          assert score.gate_ok?
          assert score.improved?
          refute score.met_target?
          assert_nil score.value
        end

        def test_has_no_protected_paths
          assert_empty Null.new.protected_paths
        end

        private

        def context
          Context.new(work_dir: Dir.pwd, previous_ref: "HEAD", previous_value: nil,
                      objective: "obj", iteration: 1)
        end
      end
    end
  end
end
