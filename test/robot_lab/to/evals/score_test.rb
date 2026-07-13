# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Evals
      class ScoreTest < Minitest::Test
        def test_predicates_reflect_fields
          score = Score.new(gate_ok: true, improved: false, met_target: true,
                            value: 42.0, detail: "d", output: "o")
          assert score.gate_ok?
          refute score.improved?
          assert score.met_target?
          assert_equal 42.0, score.value
          assert_equal "d", score.detail
          assert_equal "o", score.output
        end

        def test_is_a_value_object
          a = Score.new(gate_ok: true, improved: true, met_target: false, value: 1, detail: "d", output: nil)
          b = Score.new(gate_ok: true, improved: true, met_target: false, value: 1, detail: "d", output: nil)
          assert_equal a, b
        end
      end

      class ContextTest < Minitest::Test
        def test_carries_iteration_state
          ctx = Context.new(work_dir: "/w", previous_ref: "abc", previous_value: 80.0,
                            objective: "obj", iteration: 3)
          assert_equal "/w", ctx.work_dir
          assert_equal "abc", ctx.previous_ref
          assert_equal 80.0, ctx.previous_value
          assert_equal "obj", ctx.objective
          assert_equal 3, ctx.iteration
        end
      end
    end
  end
end
