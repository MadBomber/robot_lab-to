# frozen_string_literal: true

require "open3"

module RobotLab
  module To
    module Tools
      # Run a shell command in the working directory and return combined
      # stdout+stderr plus the exit status. Output is capped and the command is
      # killed past a timeout so a runaway process can't stall an overnight loop.
      class Bash < FileTool
        DEFAULT_TIMEOUT = 120
        MAX_OUTPUT = 30_000

        description <<~DESC
          Run a shell command in the project directory and return its combined
          output and exit status. Use for building, testing, listing, and git.
        DESC

        param :command, type: "string", desc: "The shell command to run"
        param :timeout, type: "integer", desc: "Seconds before the command is killed", required: false

        def initialize(robot: nil, timeout: DEFAULT_TIMEOUT)
          super(robot: robot)
          @default_timeout = timeout
        end

        def execute(command:, timeout: nil, **)
          out, status = run(command, (timeout || @default_timeout).to_i)
          format_result(out, status)
        end

        # Run `command`, returning [combined_output, status_string].
        # status_string is "0".."n" for an exit code, or "timeout"/"error: ...".
        #
        # @return [Array(String, String)]
        def run(command, timeout)
          out_str = +""
          status = nil
          Open3.popen2e(command, chdir: Dir.pwd) do |_stdin, out, wait|
            reader = Thread.new { out.each_char { |c| out_str << c } }
            status = finished_within?(wait, timeout) ? wait.value.exitstatus.to_s : kill(wait)
            reader.join(1)
          end
          [out_str, status]
        rescue SystemCallError, IOError => e
          ["", "error: #{e.message}"]
        end

        private

        # @return [Boolean] true if the process finished within `timeout`
        def finished_within?(wait, timeout)
          deadline = clock + timeout
          sleep(0.01) while wait.alive? && clock < deadline
          !wait.alive?
        end

        def kill(wait)
          Process.kill("TERM", wait.pid)
          "timeout"
        rescue Errno::ESRCH
          "timeout"
        end

        def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        def format_result(out, status)
          body = out.length > MAX_OUTPUT ? "#{out[0, MAX_OUTPUT]}\n[output truncated]" : out
          "[exit #{status}]\n#{body}"
        end
      end
    end
  end
end
