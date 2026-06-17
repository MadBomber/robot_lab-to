# frozen_string_literal: true

require "optparse"

module RobotLab
  module To
    # OptionParser-based CLI for robot-to.
    class CLI
      def self.run(argv = ARGV)
        new.run(argv)
      end

      def run(argv)
        opts   = {}
        parser = build_parser(opts)
        args   = parser.parse!(argv.dup)

        if opts[:version]
          puts "robot-to #{VERSION}"
          return
        end

        objective = args.first || read_stdin_objective
        if objective.nil? || objective.strip.empty?
          warn "Error: objective required (pass as argument or via stdin)"
          warn parser
          exit 1
        end

        RobotLab::To.run(objective.strip, **opts.except(:version))
      end

      private

      # rubocop:disable Metrics/MethodLength, Metrics/BlockLength, Metrics/AbcSize
      def build_parser(opts)
        OptionParser.new do |p|
          p.banner = "Usage: robot-to [objective] [options]"
          p.separator ""
          p.separator "Runs a robot_lab Robot in an autonomous loop toward the given objective."
          p.separator ""
          p.separator "Options:"

          p.on("--provider NAME", String,
               "LLM provider to use (default: openai)") do |v|
            opts[:provider] = v
          end

          p.on("--model MODEL", String,
               "LLM model to use (default: gpt-5.5)") do |v|
            opts[:model] = v
          end

          p.on("--max-iterations N", Integer,
               "Stop after N iterations (default: unlimited)") do |v|
            opts[:max_iterations] = v
          end

          p.on("--max-tokens N", Integer,
               "Stop after N total tokens (default: unlimited)") do |v|
            opts[:max_tokens] = v
          end

          p.on("--stop-when CONDITION", String,
               "Natural-language condition; robot sets should_fully_stop when met") do |v|
            opts[:stop_when] = v
          end

          p.on("--max-consecutive-failures N", Integer,
               "Abort after N consecutive failures (default: 3)") do |v|
            opts[:max_consecutive_failures] = v
          end

          p.on("--verify-command CMD", String,
               "Command that must pass before a successful iteration is committed") do |v|
            opts[:verify_command] = v
          end

          p.on("--verify-timeout SECONDS", Integer,
               "Timeout for --verify-command (default: 600)") do |v|
            opts[:verify_timeout] = v
          end

          p.on("--run-dir PATH", String,
               "Directory for run state (default: .robot_lab_to)") do |v|
            opts[:run_dir] = v
          end

          p.on("--commit-format FORMAT", %w[default conventional],
               "Commit message format: default or conventional") do |v|
            opts[:commit_format] = v
          end

          p.on("--debug", "Enable verbose JSONL logging to stderr") do
            opts[:debug] = true
          end

          p.on("--version", "Print version and exit") do
            opts[:version] = true
          end

          p.on("-h", "--help", "Show this help") do
            puts p
            exit
          end
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/BlockLength, Metrics/AbcSize

      def read_stdin_objective
        return nil if $stdin.tty?

        $stdin.read.strip.then { |s| s.empty? ? nil : s }
      end
    end
  end
end
