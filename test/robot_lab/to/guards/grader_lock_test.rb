# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Guards
      class GraderLockTest < Minitest::Test
        LOCKED = "/repo/grader/outline.md"

        def test_write_to_locked_path_is_refused
          result, proceeded = guard_call("write", { "path" => LOCKED }, [LOCKED])
          refute proceeded, "the write must be blocked"
          assert_match(/locked grader artifact/, result)
        end

        def test_edit_to_locked_path_is_refused
          _result, proceeded = guard_call("edit", { "path" => LOCKED }, [LOCKED])
          refute proceeded
        end

        def test_write_to_unrelated_path_is_allowed
          _result, proceeded = guard_call("write", { "path" => "/repo/src/main.rb" }, [LOCKED])
          assert proceeded
        end

        def test_bash_redirect_to_locked_path_is_refused
          _result, proceeded = guard_call("bash", { "command" => "echo hi > #{LOCKED}" }, [LOCKED])
          refute proceeded
        end

        def test_bash_referencing_locked_basename_is_refused
          _result, proceeded = guard_call("bash", { "command" => "vim outline.md" }, [LOCKED])
          refute proceeded
        end

        def test_bash_unrelated_command_is_allowed
          _result, proceeded = guard_call("bash", { "command" => "ls -la" }, [LOCKED])
          assert proceeded
        end

        def test_read_is_never_blocked
          _result, proceeded = guard_call("read", { "path" => LOCKED }, [LOCKED])
          assert proceeded
        end

        def test_empty_lock_set_is_a_noop
          _result, proceeded = guard_call("write", { "path" => LOCKED }, [])
          assert proceeded
        end

        private

        # Runs GraderLock.around_tool_call with the given locked paths; returns
        # [result, proceeded?] where proceeded is true when the tool ran.
        def guard_call(tool, args, paths)
          ctx = tool_ctx(tool, args)
          proceeded = false
          result = nil
          ctx.with_namespace(:grader_lock) do
            ctx.local.paths = paths
            result = GraderLock.around_tool_call(ctx) { proceeded = true }
          end
          [result, proceeded]
        end
      end
    end
  end
end
