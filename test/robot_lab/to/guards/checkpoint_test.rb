# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Guards
      class CheckpointTest < Minitest::Test
        def setup
          Thread.current[Checkpoint::KEY] = nil
        end

        def test_snapshot_backs_up_existing_file
          with_tmp_dir do |dir|
            src = dir.join("f.rb").to_s
            File.write(src, "original")
            backup = Checkpoint.snapshot(src, dir.join("cp").to_s)
            assert_equal "original", File.read(backup)
          end
        end

        def test_snapshot_writes_absent_sentinel_for_missing_file
          with_tmp_dir do |dir|
            backup = Checkpoint.snapshot(dir.join("ghost.rb").to_s, dir.join("cp").to_s)
            assert backup.end_with?(".absent")
            assert_path_exists backup
          end
        end

        def test_snapshot_is_first_write_wins
          with_tmp_dir do |dir|
            src = dir.join("f.rb").to_s
            File.write(src, "v1")
            cpdir = dir.join("cp").to_s
            Checkpoint.snapshot(src, cpdir)
            File.write(src, "v2")
            assert_nil Checkpoint.snapshot(src, cpdir), "second snapshot must be skipped"
            backup = File.join(cpdir, Checkpoint.safe_name(src))
            assert_equal "v1", File.read(backup)
          end
        end

        def test_before_tool_call_snapshots_edit_target
          with_tmp_dir do |dir|
            src = dir.join("f.rb").to_s
            File.write(src, "data")
            ctx = tool_ctx("edit", { "path" => src })
            ctx.with_namespace(:checkpoint) do
              ctx.local.run = stub_run_with_dir(dir)
              Checkpoint.before_tool_call(ctx)
            end
            backup = File.join(dir.to_s, "checkpoints", Checkpoint.safe_name(src))
            assert_path_exists backup
          end
        end

        def test_before_tool_call_ignores_non_mutating_tools
          ctx = tool_ctx("read", { "path" => "/whatever" })
          dispatch(Checkpoint, :before_tool_call, ctx)
          assert_nil Thread.current[Checkpoint::KEY]
        end

        def test_safe_name_flattens_path
          assert_equal "_a_b.rb", Checkpoint.safe_name("/a/b.rb")
        end

        private

        # A Run-like object exposing run_dir.
        def stub_run_with_dir(dir)
          Struct.new(:run_dir).new(dir.to_s)
        end
      end
    end
  end
end
