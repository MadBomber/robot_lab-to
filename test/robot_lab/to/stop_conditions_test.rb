# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class StopConditionsTest < Minitest::Test
      def config_with(**overrides)
        Config.new(max_consecutive_failures: 3, **overrides)
      end

      def test_before_raises_when_max_iterations_reached
        stub_run do |run, _dir|
          run.iteration = 5
          config = config_with(max_iterations: 5)
          sc = StopConditions.new(config, run)
          assert_raises(AbortError) { sc.before? }
        end
      end

      def test_before_passes_when_under_limit
        stub_run do |run, _dir|
          run.iteration = 4
          config = config_with(max_iterations: 5)
          sc = StopConditions.new(config, run)
          assert_nil sc.before?
        end
      end

      def test_after_raises_on_consecutive_failures
        stub_run do |run, _dir|
          run.consecutive_failures = 3
          config = config_with(max_consecutive_failures: 3)
          sc = StopConditions.new(config, run)
          assert_raises(AbortError) { sc.after? }
        end
      end

      def test_token_limit_exceeded_false_when_no_limit
        stub_run do |run, _dir|
          run.input_tokens  = 1_000_000
          run.output_tokens = 1_000_000
          sc = StopConditions.new(config_with, run)
          refute sc.token_limit_exceeded?
        end
      end

      def test_token_limit_exceeded_true_when_over
        stub_run do |run, _dir|
          run.input_tokens  = 900
          run.output_tokens = 200
          config = config_with(max_tokens: 1000)
          sc = StopConditions.new(config, run)
          assert sc.token_limit_exceeded?
        end
      end

      def test_stop_when_met_raises_when_stop_is_true
        stub_run do |run, _dir|
          config = config_with(stop_when: "all tests pass")
          result = IterationResult.new(success: true, summary: "done",
                                       key_changes: [], key_learnings: [],
                                       should_fully_stop: true)
          sc = StopConditions.new(config, run)
          assert_raises(AbortError) { sc.stop_when_met?(result) }
        end
      end

      def test_stop_when_met_returns_false_when_stop_is_false
        stub_run do |run, _dir|
          config = config_with(stop_when: "all tests pass")
          result = IterationResult.new(success: true, summary: "partial",
                                       key_changes: [], key_learnings: [],
                                       should_fully_stop: false)
          sc = StopConditions.new(config, run)
          refute sc.stop_when_met?(result)
        end
      end

      def test_before_passes_when_under_token_limit
        stub_run do |run, _dir|
          run.input_tokens  = 400
          run.output_tokens = 100
          config = config_with(max_tokens: 1_000)
          sc = StopConditions.new(config, run)
          assert_nil sc.before?  # 500 < 1000, no abort
        end
      end

      def test_before_raises_when_token_limit_exceeded
        stub_run do |run, _dir|
          run.input_tokens  = 800
          run.output_tokens = 300
          config = config_with(max_tokens: 1_000)
          sc = StopConditions.new(config, run)
          assert_raises(AbortError) { sc.before? }  # 1100 >= 1000
        end
      end

      def test_after_raises_when_token_limit_exceeded
        stub_run do |run, _dir|
          run.input_tokens  = 1_500
          run.output_tokens = 0
          config = config_with(max_tokens: 1_000)
          sc = StopConditions.new(config, run)
          assert_raises(AbortError) { sc.after? }
        end
      end
    end
  end
end
