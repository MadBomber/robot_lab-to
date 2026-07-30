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

      def test_run_dir_defaults_to_notes_parent
        run = make_run(notes_path: "/tmp/runs/abc/notes.md")
        assert_equal Pathname.new("/tmp/runs/abc"), run.run_dir
      end

      def test_decisions_path_defaults_under_run_dir
        run = make_run(notes_path: "/tmp/runs/abc/notes.md")
        assert_equal Pathname.new("/tmp/runs/abc/decisions"), run.decisions_path
      end

      def test_state_path_is_run_json_under_run_dir
        run = make_run(run_dir: "/tmp/runs/abc")
        assert_equal Pathname.new("/tmp/runs/abc/run.json"), run.state_path
      end

      def test_explicit_run_dir_and_decisions_path_override
        run = make_run(run_dir: "/data/r1", decisions_path: "/data/r1/dec")
        assert_equal Pathname.new("/data/r1"), run.run_dir
        assert_equal Pathname.new("/data/r1/dec"), run.decisions_path
      end

      def test_to_h_round_trips_through_load
        with_tmp_dir do |dir|
          run = make_run(run_dir: dir.to_s)
          run.iteration = 7
          run.commits = 3
          run.consecutive_failures = 1
          run.consecutive_errors = 2
          run.input_tokens = 900
          run.output_tokens = 400
          run.last_score_value = 87.5
          run.iterations_since_improvement = 4
          path = dir.join("run.json")
          File.write(path, JSON.pretty_generate(run.to_h))

          loaded = Run.load(path)
          assert_equal run.run_id, loaded.run_id
          assert_equal run.objective, loaded.objective
          assert_equal run.branch, loaded.branch
          assert_equal run.base_commit, loaded.base_commit
          assert_equal 7, loaded.iteration
          assert_equal 3, loaded.commits
          assert_equal 1, loaded.consecutive_failures
          assert_equal 2, loaded.consecutive_errors
          assert_equal 900, loaded.input_tokens
          assert_equal 400, loaded.output_tokens
          assert_in_delta 87.5, loaded.last_score_value
          assert_equal 4, loaded.iterations_since_improvement
        end
      end

      def test_new_run_defaults_score_trajectory
        run = make_run
        assert_nil run.last_score_value
        assert_equal 0, run.iterations_since_improvement
      end

      def test_load_restores_started_at
        with_tmp_dir do |dir|
          run = make_run(run_dir: dir.to_s)
          run.instance_variable_set(:@started_at, Time.now - 3_600)
          path = dir.join("run.json")
          File.write(path, JSON.pretty_generate(run.to_h))
          loaded = Run.load(path)
          assert_operator loaded.elapsed_seconds, :>=, 3_599
        end
      end
    end
  end
end
