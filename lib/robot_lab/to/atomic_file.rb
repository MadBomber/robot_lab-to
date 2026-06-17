# frozen_string_literal: true

require "fileutils"

module RobotLab
  module To
    # Crash-safe writes for run state (notes.md and friends).
    #
    # An overnight run rewrites its state every iteration; a crash or kill
    # mid-write must not leave a truncated file (notes.md is re-injected into
    # the next robot's prompt). The pattern: serialize writers with an flock,
    # stage the full content in a sibling temp file, fsync it, atomically
    # rename it over the target, then fsync the directory. A crash at any point
    # leaves either the previous complete file or the new complete file --
    # never a torn write.
    module AtomicFile
      class << self
        # Atomically replace +path+ with +content+.
        def write(path, content)
          path = Pathname.new(path)
          path.parent.mkpath
          with_lock(path) { replace(path, content.to_s) }
        end

        # Atomically append +text+ to +path+ (read-modify-write under lock).
        def append(path, text)
          path = Pathname.new(path)
          path.parent.mkpath
          with_lock(path) do
            existing = path.exist? ? path.read : +""
            replace(path, existing + text.to_s)
          end
        end

        private

        def replace(path, content)
          tmp = path.parent.join(".#{path.basename}.#{Process.pid}.tmp")
          File.open(tmp, "w") do |f|
            f.write(content)
            f.flush
            f.fsync
          end
          File.rename(tmp, path)
          fsync_dir(path.parent)
        ensure
          # tmp is assigned on the first line, so it is always set here; on the
          # success path the rename already moved it, so rm_f is a no-op.
          FileUtils.rm_f(tmp)
        end

        def with_lock(path)
          lock = path.parent.join(".#{path.basename}.lock")
          File.open(lock, File::RDWR | File::CREAT, 0o600) do |f|
            f.flock(File::LOCK_EX)
            yield
          end
        end

        def fsync_dir(dir)
          File.open(dir, &:fsync)
        rescue SystemCallError
          # Some filesystems/platforms reject directory fsync; best-effort.
          nil
        end
      end
    end
  end
end
