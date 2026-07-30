# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Tools
      class BashTest < Minitest::Test
        def test_runs_command_and_reports_exit_zero
          out = Bash.new.execute(command: "echo hello")
          assert_includes out, "[exit 0]"
          assert_includes out, "hello"
        end

        def test_captures_nonzero_exit
          out = Bash.new.execute(command: "exit 3")
          assert_includes out, "[exit 3]"
        end

        def test_captures_stderr
          out = Bash.new.execute(command: "echo oops 1>&2")
          assert_includes out, "oops"
        end

        def test_run_returns_output_and_status
          out, status = Bash.new.run("printf abc", 5)
          assert_equal "abc", out
          assert_equal "0", status
        end

        def test_times_out_long_command
          out, status = Bash.new.run("sleep 5", 1)
          assert_equal "timeout", status
          assert_empty out
        end
      end
    end
  end
end
