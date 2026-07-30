# frozen_string_literal: true

module RobotLab
  module To
    module Tools
      # Read a UTF-8 text file, optionally a line range. Output is capped so a
      # small local model's context can't be blown by one oversized read
      # (mirrors little-coder's read-guard intent).
      class Read < FileTool
        MAX_LINES = 2000

        description <<~DESC
          Read a text file and return its contents. Optionally pass offset (1-based
          start line) and limit (max lines). Always read a file before editing it.
        DESC

        param :path, type: "string", desc: "Path to the file to read"
        param :offset, type: "integer", desc: "1-based first line to return", required: false
        param :limit, type: "integer", desc: "Maximum number of lines to return", required: false

        def execute(path:, offset: nil, limit: nil, **)
          resolved = File.expand_path(path, Dir.pwd)
          return "Error: file not found: #{path}" unless File.file?(resolved)

          lines = File.readlines(resolved)
          slice = select_lines(lines, offset, limit)
          render(slice, lines.size, offset)
        rescue SystemCallError => e
          "Error reading #{path}: #{e.message}"
        end

        # @return [Array<String>] the chosen lines, capped at MAX_LINES
        def select_lines(lines, offset, limit)
          start = offset ? [offset.to_i - 1, 0].max : 0
          count = limit ? limit.to_i : MAX_LINES
          lines[start, [count, MAX_LINES].min] || []
        end

        private

        def render(slice, total, offset)
          body = slice.join
          start = offset ? offset.to_i : 1
          shown = slice.size
          return "(empty file)" if total.zero?

          if start + shown - 1 < total
            "#{body}\n[truncated: showed #{shown} of #{total} lines starting at #{start}; " \
              "use offset/limit to read more]"
          else
            body
          end
        end
      end
    end
  end
end
