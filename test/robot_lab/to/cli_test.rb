# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class CLITest < Minitest::Test
      def captured_run_args(argv)
        received = {}
        fake = ->(_obj, **opts) { received = opts }
        RobotLab::To.stub(:run, fake) { CLI.run(argv) }
        received
      end

      def test_version_flag_prints_version
        out, = capture_io { CLI.run(["--version"]) }
        assert_match(/robot-to \d+\.\d+/, out)
      end

      def test_objective_passed_to_run
        received_obj = nil
        fake = ->(obj, **) { received_obj = obj }
        RobotLab::To.stub(:run, fake) { CLI.run(["fix the tests"]) }
        assert_equal "fix the tests", received_obj
      end

      def test_model_flag
        opts = captured_run_args(["do work", "--model", "claude-opus-4"])
        assert_equal "claude-opus-4", opts[:model]
      end

      def test_max_iterations_flag
        opts = captured_run_args(["do work", "--max-iterations", "5"])
        assert_equal 5, opts[:max_iterations]
      end

      def test_max_tokens_flag
        opts = captured_run_args(["do work", "--max-tokens", "50000"])
        assert_equal 50_000, opts[:max_tokens]
      end

      def test_stop_when_flag
        opts = captured_run_args(["do work", "--stop-when", "all tests pass"])
        assert_equal "all tests pass", opts[:stop_when]
      end

      def test_debug_flag
        opts = captured_run_args(["do work", "--debug"])
        assert opts[:debug]
      end

      def test_local_guards_flag
        opts = captured_run_args(["do work", "--local-guards"])
        assert opts[:local_guards]
      end

      def test_no_stream_flag
        opts = captured_run_args(["do work", "--no-stream"])
        assert_equal false, opts[:stream]
      end

      def test_commit_format_conventional
        opts = captured_run_args(["do work", "--commit-format", "conventional"])
        assert_equal "conventional", opts[:commit_format]
      end

      def test_max_consecutive_failures_flag
        opts = captured_run_args(["do work", "--max-consecutive-failures", "7"])
        assert_equal 7, opts[:max_consecutive_failures]
      end

      def test_max_verify_repairs_flag
        opts = captured_run_args(["do work", "--max-verify-repairs", "4"])
        assert_equal 4, opts[:max_verify_repairs]
      end

      def test_run_dir_flag
        opts = captured_run_args(["do work", "--run-dir", "/tmp/runs"])
        assert_equal "/tmp/runs", opts[:run_dir]
      end

      def test_version_not_passed_to_run
        opts = {}
        fake = ->(_obj, **o) { opts = o }
        RobotLab::To.stub(:run, fake) { CLI.run(["do work"]) }
        refute opts.key?(:version)
      end

      def test_help_flag_exits
        assert_raises(SystemExit) { CLI.run(["--help"]) }
      end

      def test_missing_objective_exits_with_error
        original_stdin = $stdin
        $stdin = StringIO.new("")
        out, err = capture_io do
          assert_raises(SystemExit) { CLI.run([]) }
        end
        assert_includes err, "objective required"
        assert_empty out
      ensure
        $stdin = original_stdin
      end

      def test_decision_mode_flag
        opts = captured_run_args(["do work", "--decision-mode", "exit"])
        assert_equal "exit", opts[:decision_mode]
      end

      def test_decision_timeout_and_poll_flags
        opts = captured_run_args(["do work", "--decision-timeout", "3600", "--decision-poll", "15"])
        assert_equal 3_600, opts[:decision_timeout]
        assert_equal 15, opts[:decision_wait_poll]
      end

      def test_no_decisions_flag
        opts = captured_run_args(["do work", "--no-decisions"])
        assert_equal false, opts[:decisions_enabled]
      end

      def test_eval_flag
        opts = captured_run_args(["do work", "--eval", "code"])
        assert_equal "code", opts[:eval]
      end

      def test_measure_flag
        opts = captured_run_args(["do work", "--measure", "rake coverage"])
        assert_equal "rake coverage", opts[:eval_measure]
      end

      def test_target_flag
        opts = captured_run_args(["do work", "--target", "90"])
        assert_in_delta 90.0, opts[:eval_target]
      end

      def test_stop_on_plateau_flag
        opts = captured_run_args(["do work", "--stop-on-plateau", "3"])
        assert_equal 3, opts[:stop_on_plateau]
      end

      def test_no_require_improvement_flag
        opts = captured_run_args(["do work", "--no-require-improvement"])
        assert_equal false, opts[:require_improvement]
      end

      def test_require_improvement_flag_on
        opts = captured_run_args(["do work", "--require-improvement"])
        assert_equal true, opts[:require_improvement]
      end

      def test_resume_routes_to_resume_with_run_id
        received = nil
        opts = {}
        fake = lambda do |run_id, **o|
          received = run_id
          opts = o
        end
        RobotLab::To.stub(:resume, fake) { CLI.run(["--resume", "20260701-120000-abc123"]) }
        assert_equal "20260701-120000-abc123", received
        refute opts.key?(:resume)
        refute opts.key?(:version)
      end

      def test_decisions_subcommand_no_runs_exits
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            _out, err = capture_io do
              assert_raises(SystemExit) { CLI.run(["decisions"]) }
            end
            assert_includes err, "No runs found"
          end
        end
      end

      def test_decisions_subcommand_lists_pending
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            run_id = "20260701-120000-abc123"
            mgr = DecisionManager.new(File.join(dir, ".robot_lab_to", "runs", run_id, "decisions"))
            mgr.setup
            mgr.record(question: "404 or 410?", blocking: true, iteration: 1)
            out, = capture_io { CLI.run(["decisions", run_id]) }
            assert_includes out, run_id
            assert_includes out, "404 or 410?"
            assert_includes out, "[BLOCKING]"
          end
        end
      end
    end
  end
end
