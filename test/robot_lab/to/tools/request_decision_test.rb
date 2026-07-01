# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Tools
      class RequestDecisionTest < Minitest::Test
        def test_captured_requests_empty_before_call
          assert_empty RequestDecision.new.captured_requests
        end

        def test_captures_a_request
          tool = RequestDecision.new
          tool.execute(question: "404 or 410?", situation: "public API",
                       options: %w[404 410], recommendation: "410", blocking: true)
          req = tool.captured_requests.first
          assert_equal "404 or 410?", req[:question]
          assert_equal "public API", req[:situation]
          assert_equal %w[404 410], req[:options]
          assert_equal "410", req[:recommendation]
          assert_equal true, req[:blocking]
        end

        def test_captures_multiple_requests
          tool = RequestDecision.new
          tool.execute(question: "first")
          tool.execute(question: "second")
          questions = tool.captured_requests.map { |r| r[:question] }
          assert_equal %w[first second], questions
        end

        def test_defaults_are_safe
          tool = RequestDecision.new
          tool.execute(question: "only question")
          req = tool.captured_requests.first
          assert_equal "", req[:situation]
          assert_equal [], req[:options]
          assert_equal "", req[:recommendation]
          assert_equal false, req[:blocking]
        end

        def test_blocking_message_tells_robot_to_stop
          result = RequestDecision.new.execute(question: "Q?", blocking: true)
          assert_match(/BLOCKING/i, result)
          assert_match(/submit/i, result)
        end

        def test_non_blocking_message_tells_robot_to_continue
          result = RequestDecision.new.execute(question: "Q?", blocking: false)
          assert_match(/continue/i, result)
        end

        def test_each_instance_is_independent
          t1 = RequestDecision.new
          t2 = RequestDecision.new
          t1.execute(question: "one")
          assert_empty t2.captured_requests
        end
      end
    end
  end
end
