# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Evals
      class CodeTest < Minitest::Test
        def test_no_verify_and_no_measure_is_open_gate_and_progress
          score = Code.new.score(context)
          assert score.gate_ok?
          assert score.improved?, "any change is progress when nothing is measured"
          refute score.met_target?
          assert_nil score.value
        end

        def test_passing_verify_opens_the_gate
          assert Code.new(verify: "true").score(context).gate_ok?
        end

        def test_failing_verify_closes_the_gate_and_captures_output
          score = Code.new(verify: "echo boom; exit 1").score(context)
          refute score.gate_ok?
          assert_includes score.output, "boom"
        end

        def test_measure_parses_first_number_as_value
          score = Code.new(measure: "echo 87.5").score(context)
          assert_in_delta 87.5, score.value
        end

        def test_improved_when_value_beats_parent
          score = Code.new(measure: "echo 90").score(context(previous_value: 80.0))
          assert score.improved?
        end

        def test_not_improved_when_value_does_not_beat_parent
          score = Code.new(measure: "echo 90").score(context(previous_value: 95.0))
          refute score.improved?
        end

        def test_first_measured_iteration_counts_as_improvement
          score = Code.new(measure: "echo 12").score(context(previous_value: nil))
          assert score.improved?
        end

        def test_met_target_when_value_reaches_target
          assert Code.new(measure: "echo 90", target: 90.0).score(context).met_target?
        end

        def test_not_met_target_below_target
          refute Code.new(measure: "echo 89", target: 90.0).score(context).met_target?
        end

        def test_no_target_never_meets
          refute Code.new(measure: "echo 500").score(context).met_target?
        end

        def test_detail_summarizes_gate_and_measure
          detail = Code.new(verify: "true", measure: "echo 42").score(context).detail
          assert_includes detail, "verify=true"
          assert_includes detail, "measure=42"
        end

        private

        def context(previous_value: nil)
          Context.new(work_dir: Dir.pwd, previous_ref: "HEAD", previous_value: previous_value,
                      objective: "obj", iteration: 1)
        end
      end
    end
  end
end
