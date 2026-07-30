# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class VerifierTest < Minitest::Test
      def test_zero_exit_passes
        assert Verifier.new("true").run.passed?
      end

      def test_nonzero_exit_does_not_pass
        refute Verifier.new("exit 7").run.passed?
      end

      def test_captures_command_output
        result = Verifier.new("echo marker_xyz; exit 1").run
        refute result.passed?
        assert_includes result.output, "marker_xyz"
      end

      def test_runs_in_work_dir
        with_tmp_dir do |dir|
          dir.join("sentinel_file").write("x")
          result = Verifier.new("ls", work_dir: dir.to_s).run
          assert result.passed?
          assert_includes result.output, "sentinel_file"
        end
      end

      def test_timeout_fails_and_reports
        result = Verifier.new("sleep 5", timeout: 0.2).run
        refute result.passed?
        assert_includes result.output, "timed out"
      end

      def test_output_is_clamped
        result = Verifier.new(%q(ruby -e 'print "a" * 6000')).run
        assert result.passed?
        assert_operator result.output.length, :<=, Verifier::MAX_OUTPUT + 32
        assert_includes result.output, "truncated"
      end
    end
  end
end
