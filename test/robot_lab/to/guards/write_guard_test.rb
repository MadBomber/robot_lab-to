# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Guards
      class WriteGuardTest < Minitest::Test
        def test_write_tool_predicate_is_case_insensitive
          assert WriteGuard.write_tool?("Write")
          assert WriteGuard.write_tool?("write")
          refute WriteGuard.write_tool?("edit")
        end

        def test_around_blocks_write_to_existing_file
          with_tmp_dir do |dir|
            path = dir.join("a.rb").to_s
            File.write(path, "x")
            ctx = tool_ctx("write", { "path" => path, "content" => "y" })

            result = dispatch(WriteGuard, :around_tool_call, ctx) { :EXECUTED }

            refute_equal :EXECUTED, result
            assert_includes result, "already exists"
            assert_equal "x", File.read(path), "original must be untouched"
          end
        end

        def test_around_allows_write_to_new_file
          with_tmp_dir do |dir|
            ctx = tool_ctx("write", { "path" => dir.join("new.rb").to_s, "content" => "y" })
            result = dispatch(WriteGuard, :around_tool_call, ctx) { :EXECUTED }
            assert_equal :EXECUTED, result
          end
        end

        def test_around_passes_through_non_write_tools
          ctx = tool_ctx("edit", { "path" => "/whatever" })
          assert_equal :EXECUTED, dispatch(WriteGuard, :around_tool_call, ctx) { :EXECUTED }
        end

        def test_before_normalizes_root_bare_path_in_place
          ctx = tool_ctx("write", { "path" => "/bare.rb", "content" => "x" })
          dispatch(WriteGuard, :before_tool_call, ctx)
          assert_equal File.join(Dir.pwd, "bare.rb"), ctx.tool_args["path"]
        end
      end
    end
  end
end
