# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class ConfigTest < Minitest::Test
      def test_default_provider
        assert_equal "openai", Config.new.provider
      end

      def test_default_model
        assert_equal "gpt-5.5", Config.new.model
      end

      def test_default_max_consecutive_failures
        assert_equal 3, Config.new.max_consecutive_failures
      end

      def test_default_max_tool_rounds
        assert_equal 100, Config.new.max_tool_rounds
      end

      def test_default_max_retries
        assert_equal 2, Config.new.max_retries
      end

      def test_default_max_submit_nudges
        assert_equal 1, Config.new.max_submit_nudges
      end

      def test_max_submit_nudges_override
        assert_equal 0, Config.new(max_submit_nudges: 0).max_submit_nudges
      end

      def test_verify_command_nil_by_default
        assert_nil Config.new.verify_command
      end

      def test_verify_command_override
        assert_equal "rake test", Config.new(verify_command: "rake test").verify_command
      end

      def test_default_verify_timeout
        assert_equal 600, Config.new.verify_timeout
      end

      def test_default_commit_format
        assert_equal "default", Config.new.commit_format
      end

      def test_default_run_dir
        assert_equal ".robot_lab_to", Config.new.run_dir
      end

      def test_debug_false_by_default
        refute Config.new.debug?
      end

      def test_max_iterations_nil_by_default
        assert_nil Config.new.max_iterations
      end

      def test_max_tokens_nil_by_default
        assert_nil Config.new.max_tokens
      end

      def test_stop_when_nil_by_default
        assert_nil Config.new.stop_when
      end

      def test_model_override_via_constructor
        config = Config.new(model: "claude-opus-4")
        assert_equal "claude-opus-4", config.model
      end

      def test_max_iterations_override
        config = Config.new(max_iterations: 5)
        assert_equal 5, config.max_iterations
      end

      def test_max_tokens_override
        config = Config.new(max_tokens: 100_000)
        assert_equal 100_000, config.max_tokens
      end

      def test_stop_when_override
        config = Config.new(stop_when: "all tests pass")
        assert_equal "all tests pass", config.stop_when
      end

      def test_debug_override
        config = Config.new(debug: true)
        assert config.debug?
      end

      def test_commit_format_override
        config = Config.new(commit_format: "conventional")
        assert_equal "conventional", config.commit_format
      end

      def test_max_consecutive_failures_override
        config = Config.new(max_consecutive_failures: 10)
        assert_equal 10, config.max_consecutive_failures
      end

      def test_run_dir_override
        config = Config.new(run_dir: "/tmp/robot_runs")
        assert_equal "/tmp/robot_runs", config.run_dir
      end

      def test_unknown_override_key_ignored
        Config.new(nonexistent_key: "value")  # should not raise
      end
    end
  end
end
