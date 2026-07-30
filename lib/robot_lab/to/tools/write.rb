# frozen_string_literal: true

require "fileutils"

module RobotLab
  module To
    module Tools
      # Create a NEW file with the given contents. Parent directories are
      # created as needed. The WriteGuard refuses this on files that already
      # exist (use Edit instead) — small models otherwise rewrite whole files
      # and destroy content.
      class Write < FileTool
        description <<~DESC
          Create a new file with the given content. Use this only for files that
          do not exist yet; to change an existing file, use Edit.
        DESC

        param :path, type: "string", desc: "Path of the file to create"
        param :content, type: "string", desc: "Full text content to write"

        def execute(path:, content:, **)
          resolved = File.expand_path(path, Dir.pwd)
          FileUtils.mkdir_p(File.dirname(resolved))
          File.write(resolved, content.to_s)
          "Wrote #{content.to_s.lines.size} lines to #{path}"
        rescue SystemCallError => e
          "Error writing #{path}: #{e.message}"
        end
      end
    end
  end
end
