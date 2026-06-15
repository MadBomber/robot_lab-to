# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class RunTest < Minitest::Test
      def make_run(**overrides)
        defaults = {
          run_id: "20260615-120000-abc123",
          objective: "improve coverage",
          branch: "robot-to/improve-coverage-20260615-120000",
          base_commit: "deadbeef",
          notes_path: "/tmp/notes.md",
          log_path: "/tmp/run.log"
        }
        Run.new(**defaults, **overrides)
      end

      def test_total_tokens_sums_input_and_output
        run = make_run
        run.input_tokens  = 1_000
        run.output_tokens = 250
        assert_equal 1_250, run.total_tokens
      end

      def test_elapsed_human_seconds_only
        run = make_run
        run.instance_variable_set(:@started_at, Time.now - 42)
        assert_match(/\A\d+s\z/, run.elapsed_human)
      end

      def test_elapsed_human_minutes_and_seconds
        run = make_run
        run.instance_variable_set(:@started_at, Time.now - 125)
        assert_match(/\A\d+m \d+s\z/, run.elapsed_human)
      end

      def test_elapsed_human_hours_minutes_seconds
        run = make_run
        run.instance_variable_set(:@started_at, Time.now - 3_661)
        assert_match(/\A\d+h \d+m \d+s\z/, run.elapsed_human)
      end

      def test_generate_id_format
        id = Run.generate_id
        assert_match(/\A\d{8}-\d{6}-[0-9a-f]{6}\z/, id)
      end

      def test_generate_id_is_unique
        ids = Array.new(5) { Run.generate_id }
        assert_equal ids.uniq.length, ids.length
      end

      def test_slugify_lowercases_and_replaces_spaces
        assert_equal "fix-the-bug", Run.slugify("Fix the Bug")
      end

      def test_slugify_strips_special_chars
        assert_equal "add-feature", Run.slugify("add! feature?")
      end

      def test_slugify_truncates_at_40_chars
        long = "a" * 50
        assert_equal 40, Run.slugify(long).length
      end

      def test_slugify_empty_returns_takeover
        assert_equal "takeover", Run.slugify("")
        assert_equal "takeover", Run.slugify("!!!???")
      end

      def test_branch_name_includes_slug
        branch = Run.branch_name("fix the bug")
        assert branch.start_with?("robot-to/fix-the-bug-")
      end

      def test_initial_counters_are_zero
        run = make_run
        assert_equal 0, run.iteration
        assert_equal 0, run.commits
        assert_equal 0, run.input_tokens
        assert_equal 0, run.output_tokens
        assert_equal 0, run.consecutive_failures
        assert_equal 0, run.consecutive_errors
      end
    end
  end
end
