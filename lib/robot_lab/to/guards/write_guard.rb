# frozen_string_literal: true

require_relative "path_resolution"

module RobotLab
  module To
    module Guards
      # Refuses Write on a file that already exists, redirecting the model to
      # Edit, and normalizes root-bare paths to cwd. Ported from little-coder
      # write-guard: small models rewrite whole files and destroy content; the
      # whitepaper notes this refusal fires on ~57% of Polyglot exercises.
      #
      # Tool names matched (case-insensitive): "write".
      class WriteGuard < RobotLab::Hook
        self.namespace = :write_guard

        WRITE_TOOLS = %w[write].freeze

        class << self
          # Normalize the path in place before the tool runs (applies even when
          # we don't block — e.g. the "/foo.md" -> cwd rewrite).
          def before_tool_call(ctx)
            return unless write_tool?(ctx.tool_name)

            args = ctx.tool_args
            resolved = PathResolution.resolve(args)
            return unless resolved

            key = PathResolution::PATH_KEYS.find { |k| args.key?(k) || args.key?(k.to_sym) }
            args[key] = resolved if key
          end

          # Block the write when the target already exists.
          def around_tool_call(ctx)
            unless write_tool?(ctx.tool_name)
              return yield
            end

            resolved = PathResolution.resolve(ctx.tool_args)
            if resolved && File.exist?(resolved)
              ctx.tool_result = edit_recipe(resolved)
              return ctx.tool_result
            end

            yield
          end

          # @param tool_name [String]
          # @return [Boolean]
          def write_tool?(tool_name)
            WRITE_TOOLS.include?(tool_name.to_s.downcase)
          end

          # The message returned to the model in place of the refused write.
          #
          # @param resolved [String]
          # @return [String]
          def edit_recipe(resolved)
            <<~MSG
              Write refused — #{resolved} already exists. Write is for creating
              NEW files only. To change an existing file, Read it first to get the
              exact current text, then use Edit with that text as oldText
              (whitespace and indentation must match). Do NOT retry Write; it will
              be refused again.
            MSG
          end
        end
      end
    end
  end
end
