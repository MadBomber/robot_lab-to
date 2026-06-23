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
    end
  end
end
