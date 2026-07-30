# frozen_string_literal: true

require "open3"
require "timeout"

module RobotLab
  module To
    # Runs an independent verification command (e.g. the test suite) to confirm
    # a robot's self-reported success before the orchestrator commits.
    #
    # This is the single-robot translation of separation-of-duties: the deciding
    # authority is a real command run by the orchestrator, not the robot, so the
    # robot cannot self-certify a passing verdict. A non-zero exit -- or a
    # timeout -- fails the gate.
    class Verifier
      MAX_OUTPUT = 4_000

      Result = Data.define(:passed, :output) do
        def passed? = passed
      end

      def initialize(command, work_dir: Dir.pwd, timeout: 600)
        @command  = command
        @work_dir = work_dir
        @timeout  = timeout
      end

      def run
        output, ok = capture
        Result.new(passed: ok, output: clamp(output))
      end

      private

      def capture
        # pgroup: true so a timeout can kill the whole process tree (test
        # runners spawn children), not just the shell.
        Open3.popen2e(@command, chdir: @work_dir, pgroup: true) do |stdin, out, wait|
          stdin.close
          collected = +""
          begin
            Timeout.timeout(@timeout) { collected << out.read }
          rescue Timeout::Error
            terminate(wait.pid)
            return ["#{collected}\n[verification timed out after #{@timeout}s]", false]
          end
          [collected, wait.value.success?]
        end
      end

      def terminate(pid)
        Process.kill("-TERM", Process.getpgid(pid))
      rescue StandardError
        nil
      end

      def clamp(text)
        t = text.to_s.strip
        t.length > MAX_OUTPUT ? "#{t[0, MAX_OUTPUT]}\n[output truncated]" : t
      end
    end
  end
end
