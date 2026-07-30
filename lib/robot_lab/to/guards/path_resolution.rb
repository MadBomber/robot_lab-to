# frozen_string_literal: true

module RobotLab
  module To
    module Guards
      # Shared, pure path helpers used by the file guards. No hook state here so
      # each function is trivially testable in isolation.
      module PathResolution
        module_function

        # Keys a tool might use to carry the destination path.
        PATH_KEYS = %w[path file_path].freeze

        # Extract the raw path string from tool args, accepting either `path`
        # (RubyLLM/MCP style) or `file_path`.
        #
        # @param args [Hash]
        # @return [String, nil]
        def raw_path(args)
          key = PATH_KEYS.find { |k| args[k].is_a?(String) || args[k.to_sym].is_a?(String) }
          return nil unless key

          (args[key] || args[key.to_sym]).to_s
        end

        # Normalize a model-supplied path against cwd.
        #
        # Two deterministic rewrites (ported from little-coder write-guard):
        #   1. "/<single-segment>" (e.g. "/foo.md") -> "<cwd>/foo.md" — small
        #      models anchor at filesystem root when handed an "absolute path"
        #      schema; a real system path always has an intermediate dir.
        #   2. bare/relative path -> resolved against cwd.
        # Any absolute path with an intermediate directory is left untouched.
        #
        # @param file_path [String]
        # @param cwd [String]
        # @return [String] the resolved absolute path
        def normalize(file_path, cwd: Dir.pwd)
          if file_path.match?(%r{\A/[^/]+\z})
            File.join(cwd, file_path.delete_prefix("/"))
          elsif !file_path.start_with?("/")
            File.join(cwd, file_path)
          else
            file_path
          end
        end

        # Resolve a tool's path argument to a concrete absolute path, or nil if
        # the args carry no resolvable path.
        #
        # @param args [Hash]
        # @param cwd [String]
        # @return [String, nil]
        def resolve(args, cwd: Dir.pwd)
          raw = raw_path(args)
          raw && normalize(raw, cwd: cwd)
        end
      end
    end
  end
end
