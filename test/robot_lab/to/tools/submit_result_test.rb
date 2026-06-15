# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Tools
      class SubmitResultTest < Minitest::Test
        def test_captured_result_nil_before_call
          tool = SubmitResult.new
          assert_nil tool.captured_result
        end

        def test_captures_result_on_execute
          tool = SubmitResult.new
          tool.execute(success: true, summary: "added feature",
                       key_changes: ["lib/foo.rb"], key_learnings: ["use memoize"])
          result = tool.captured_result
          assert result.success?
          assert_equal "added feature", result.summary
          assert_equal ["lib/foo.rb"], result.key_changes
          assert_equal ["use memoize"], result.key_learnings
        end

        def test_captures_failure_result
          tool = SubmitResult.new
          tool.execute(success: false, summary: "tests broken")
          refute tool.captured_result.success?
        end

        def test_should_fully_stop_defaults_to_nil
          tool = SubmitResult.new
          tool.execute(success: true, summary: "ok")
          assert_nil tool.captured_result.should_fully_stop
        end

        def test_should_fully_stop_captured
          tool = SubmitResult.new
          tool.execute(success: true, summary: "done", should_fully_stop: true)
          assert tool.captured_result.stop?
        end

        def test_returns_completion_string
          tool = SubmitResult.new
          result = tool.execute(success: true, summary: "ok")
          assert_match(/complete/i, result)
        end

        def test_each_instance_is_independent
          t1 = SubmitResult.new
          t2 = SubmitResult.new
          t1.execute(success: true, summary: "first")
          assert_nil t2.captured_result
        end
      end
    end
  end
end
