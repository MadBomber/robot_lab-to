# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class IterationResultTest < Minitest::Test
      def test_success_predicate
        r = IterationResult.new(success: true, summary: "did stuff",
                                key_changes: [], key_learnings: [], should_fully_stop: nil)
        assert r.success?
      end

      def test_failure_predicate
        r = IterationResult.new(success: false, summary: "nothing",
                                key_changes: [], key_learnings: [], should_fully_stop: nil)
        refute r.success?
      end

      def test_stop_predicate_true
        r = IterationResult.new(success: true, summary: "done",
                                key_changes: [], key_learnings: [], should_fully_stop: true)
        assert r.stop?
      end

      def test_stop_predicate_false_when_nil
        r = IterationResult.no_stop_when(success: true, summary: "done")
        refute r.stop?
      end

      def test_not_submitted_factory
        r = IterationResult.not_submitted
        refute r.success?
        assert_match(/submit_iteration_result/, r.summary)
      end

      def test_no_stop_when_factory_defaults
        r = IterationResult.no_stop_when(success: true, summary: "good")
        assert_equal [], r.key_changes
        assert_equal [], r.key_learnings
        assert_nil r.should_fully_stop
      end
    end
  end
end
