# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Guards
      class ReadBeforeEditTest < Minitest::Test
        def setup
          Thread.current[ReadBeforeEdit::KEY] = nil
        end

        def test_before_run_resets_read_set
          ReadBeforeEdit.read_files << "/stale"
          dispatch(ReadBeforeEdit, :before_run, run_ctx)
          assert_empty ReadBeforeEdit.read_files
        end

        def test_blocks_edit_to_unread_file
          path = File.join(Dir.pwd, "x.rb")
          ctx = tool_ctx("edit", { "path" => path })
          result = dispatch(ReadBeforeEdit, :around_tool_call, ctx) { :EXECUTED }
          refute_equal :EXECUTED, result
          assert_includes result, "must be read"
        end

        def test_allows_edit_after_read_recorded
          path = File.join(Dir.pwd, "x.rb")
          read = tool_ctx("read", { "path" => path })
          dispatch(ReadBeforeEdit, :after_tool_call, read)

          edit = tool_ctx("edit", { "path" => path })
          assert_equal :EXECUTED, dispatch(ReadBeforeEdit, :around_tool_call, edit) { :EXECUTED }
        end

        def test_after_tool_call_ignores_errored_reads
          path = File.join(Dir.pwd, "x.rb")
          ctx = tool_ctx("read", { "path" => path })
          ctx.tool_error = RuntimeError.new("boom")
          dispatch(ReadBeforeEdit, :after_tool_call, ctx)
          refute ReadBeforeEdit.read?(path)
        end

        def test_write_marks_file_readable_for_edit
          path = File.join(Dir.pwd, "authored.rb")
          wrote = tool_ctx("write", { "path" => path })
          dispatch(ReadBeforeEdit, :after_tool_call, wrote)
          assert ReadBeforeEdit.read?(path)
        end

        def test_non_edit_tools_pass_through
          ctx = tool_ctx("bash", { "command" => "ls" })
          assert_equal :EXECUTED, dispatch(ReadBeforeEdit, :around_tool_call, ctx) { :EXECUTED }
        end
      end
    end
  end
end
