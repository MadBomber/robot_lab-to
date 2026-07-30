# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "path_resolution"
require_relative "run_store"

module RobotLab
  module To
    module Guards
      # First-write-wins file snapshot before Write/Edit, ported from
      # little-coder checkpoint. Finer-grained than robot_lab-to's git rollback:
      # it survives WITHIN an iteration, so the model (or a future repair step)
      # can revert a single botched edit without discarding the iteration's good
      # work. Best-effort — never raises into the tool path.
      #
      # Backups land under <run_dir>/checkpoints/, falling back to a temp dir
      # when no Run is supplied. Files that did not exist get a `.absent`
      # sentinel. The snapshotted-set spans calls, so it lives in RunStore.
      class Checkpoint < RobotLab::Hook
        self.namespace = :checkpoint

        KEY = :robot_lab_to_checkpoint
        MUTATING_TOOLS = %w[write edit].freeze

        class << self
          def before_run(_ctx)
            RunStore.reset(KEY, [])
          end

          def before_tool_call(ctx)
            return unless MUTATING_TOOLS.include?(ctx.tool_name.to_s.downcase)

            path = PathResolution.resolve(ctx.tool_args)
            return unless path

            snapshot(path, checkpoint_dir(ctx))
          end

          # Copy `path`'s current bytes into `dir`, once per run (first-write
          # wins). Swallows all I/O errors — checkpointing must never break a
          # tool call.
          #
          # @return [String, nil] the backup path written, or nil if skipped
          def snapshot(path, dir)
            tracked = RunStore.fetch(KEY, [])
            return if tracked.include?(path)

            tracked << path
            FileUtils.mkdir_p(dir)
            dest = File.join(dir, safe_name(path))
            if File.exist?(path)
              FileUtils.cp(path, dest)
              dest
            else
              File.write("#{dest}.absent", "")
              "#{dest}.absent"
            end
          rescue SystemCallError, IOError
            nil
          end

          # @return [String] directory for this run's checkpoints (created)
          def checkpoint_dir(ctx)
            run  = ctx.local.run
            base = run.respond_to?(:run_dir) ? run.run_dir : Dir.tmpdir
            dir  = File.join(base.to_s, "checkpoints")
            FileUtils.mkdir_p(dir)
            dir
          end

          # Flatten an absolute path into a single safe filename.
          #
          # @param path [String]
          # @return [String]
          def safe_name(path)
            flat = path.gsub(/[^A-Za-z0-9._-]/, "_")
            flat.length > 200 ? flat[-200..] : flat
          end
        end
      end
    end
  end
end
