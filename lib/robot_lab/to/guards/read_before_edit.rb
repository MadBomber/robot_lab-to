# frozen_string_literal: true

require_relative "path_resolution"
require_relative "run_store"

module RobotLab
  module To
    module Guards
      # Read-before-edit invariant, ported from little-coder read-guard-edit.
      #
      # Small models fire Edit with an oldText they never actually saw, guessing
      # the file's contents — which either fails the exact-match (wasted turn) or
      # matches the wrong span (silent corruption). We block any Edit whose
      # target wasn't Read this run.
      #
      # The read-set spans many tool calls within one run, so it lives in the
      # per-run RunStore (see that file for why ctx.local can't hold it). A
      # successful Read, Edit, or Write marks the path as known.
      class ReadBeforeEdit < RobotLab::Hook
        self.namespace = :read_before_edit

        KEY = :robot_lab_to_read_files
        TRACKED_READS = %w[read edit write].freeze

        class << self
          # Fresh run = clean slate; a prior iteration's reads say nothing here.
          def before_run(_ctx)
            RunStore.reset(KEY, [])
          end

          # Record successful reads/authored files as "known".
          def after_tool_call(ctx)
            return if ctx.tool_error
            return unless TRACKED_READS.include?(ctx.tool_name.to_s.downcase)

            path = PathResolution.resolve(ctx.tool_args)
            mark_read(path) if path
          end

          # Block edits to files that were never read.
          def around_tool_call(ctx)
            return yield unless ctx.tool_name.to_s.casecmp?("edit")

            path = PathResolution.resolve(ctx.tool_args)
            if path && !read?(path)
              ctx.tool_result = edit_before_read_reason(path)
              return ctx.tool_result
            end

            yield
          end

          # @return [Boolean] whether `path` has been read this run
          def read?(path)
            read_files.include?(path)
          end

          def mark_read(path)
            files = read_files
            files << path unless files.include?(path)
          end

          # @return [Array<String>] the per-run read-set (live reference)
          def read_files
            RunStore.fetch(KEY, [])
          end

          # @param resolved [String]
          # @return [String]
          def edit_before_read_reason(resolved)
            <<~MSG
              File must be read before edit — #{resolved} has not been read in
              this session. Read #{resolved} first to get the exact current text
              for oldText (whitespace and indentation must match exactly), then
              issue the Edit. Include 2-3 surrounding lines so oldText is unique.
              Do NOT guess the file's contents.
            MSG
          end
        end
      end
    end
  end
end
