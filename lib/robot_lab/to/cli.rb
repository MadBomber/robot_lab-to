# frozen_string_literal: true

require "optparse"

module RobotLab
  module To
    # OptionParser-based CLI for robot-to.
    class CLI
      # Value options: [flag, type-or-choices, description, opts-key]. Each sets
      # opts[key] = parsed value. Kept as data so build_parser stays simple.
      VALUE_OPTIONS = [
        ["--provider NAME", String, "LLM provider to use (default: openai)", :provider],
        ["--model MODEL", String, "LLM model to use (default: gpt-5.5)", :model],
        ["--max-iterations N", Integer, "Stop after N iterations (default: unlimited)", :max_iterations],
        ["--max-tokens N", Integer, "Stop after N total tokens (default: unlimited)", :max_tokens],
        ["--stop-when CONDITION", String,
         "Natural-language condition; robot sets should_fully_stop when met", :stop_when],
        ["--max-consecutive-failures N", Integer,
         "Abort after N consecutive failures (default: 3)", :max_consecutive_failures],
        ["--max-verify-repairs N", Integer,
         "Repair-in-place attempts when --verify-command fails (default: 2)", :max_verify_repairs],
        ["--verify-command CMD", String,
         "Command that must pass before a successful iteration is committed", :verify_command],
        ["--verify-timeout SECONDS", Integer, "Timeout for --verify-command (default: 600)", :verify_timeout],
        ["--run-dir PATH", String, "Directory for run state (default: .robot_lab_to)", :run_dir],
        ["--commit-format FORMAT", %w[default conventional],
         "Commit message format: default or conventional", :commit_format],
        ["--resume RUN_ID", String,
         "Resume a paused run (loads objective + state from its run.json)", :resume],
        ["--decision-mode MODE", %w[wait exit],
         "On a blocking decision: wait (poll) or exit (stop for --resume). Default: wait", :decision_mode],
        ["--decision-timeout SECONDS", Integer,
         "Max seconds to wait on a blocking decision (default: no limit)", :decision_timeout],
        ["--decision-poll SECONDS", Integer,
         "Seconds between polls while waiting on a decision (default: 30)", :decision_wait_poll]
      ].freeze

      def self.run(argv = ARGV)
        new.run(argv)
      end

      def run(argv)
        return run_decisions(argv[1..] || []) if argv.first == "decisions"

        opts   = {}
        parser = build_parser(opts)
        args   = parser.parse!(argv.dup)

        if opts[:version]
          puts "robot-to #{VERSION}"
          return
        end

        if opts[:resume]
          return RobotLab::To.resume(opts[:resume], **opts.except(:version, :resume))
        end

        objective = args.first || read_stdin_objective
        if objective.nil? || objective.strip.empty?
          # $stderr.puts, not warn: warn is silenced when $VERBOSE is nil.
          $stderr.puts "Error: objective required (pass as argument or via stdin)"
          $stderr.puts parser
          exit 1
        end

        RobotLab::To.run(objective.strip, **opts.except(:version, :resume))
      end

      private

      # `robot-to decisions [run_id]` — list pending decisions and their file
      # paths so a human knows what needs resolving before resuming.
      def run_decisions(args)
        run_dir = Config.new.run_dir
        run_id  = args.first || latest_run_id(run_dir)
        if run_id.nil?
          $stderr.puts "No runs found under #{run_dir}/runs"
          exit 1
        end

        manager = DecisionManager.new(Pathname.new(run_dir).join("runs", run_id, "decisions"))
        print_decisions(run_id, manager)
      end

      def print_decisions(run_id, manager)
        pending  = manager.pending
        resolved = manager.resolved_open
        puts "Run #{run_id}"
        puts ""
        if pending.empty? && resolved.empty?
          puts "No open decisions."
          return
        end
        list_group("Pending (awaiting your answer)", pending)
        list_group("Resolved (not yet consumed)", resolved)
        puts ""
        puts "Resolve a pending decision by editing its file: set `status: resolved`"
        puts "and fill `resolution:`, then run `robot-to --resume #{run_id}`."
      end

      def list_group(title, decisions)
        return if decisions.empty?

        puts "#{title}:"
        decisions.each do |d|
          flag = d.blocking? ? " [BLOCKING]" : ""
          puts "  - #{d.question}#{flag}"
          puts "    #{d.path}"
        end
        puts ""
      end

      def latest_run_id(run_dir)
        Dir.glob(Pathname.new(run_dir).join("runs", "*")).select { |p| File.directory?(p) }
                                                         .sort.map { |p| File.basename(p) }.last
      end

      def build_parser(opts)
        OptionParser.new do |p|
          p.banner = "Usage: robot-to [objective] [options]\n       " \
                     "robot-to --resume RUN_ID [options]\n       " \
                     "robot-to decisions [RUN_ID]"
          p.separator ""
          p.separator "Runs a robot_lab Robot in an autonomous loop toward the given objective."
          p.separator ""
          p.separator "Options:"

          VALUE_OPTIONS.each do |flag, type, desc, key|
            p.on(flag, type, desc) { |v| opts[key] = v }
          end

          add_flag_options(p, opts)
        end
      end

      # Boolean and terminal flags (each has bespoke behavior).
      def add_flag_options(parser, opts)
        parser.on("--no-decisions", "Disable the request_decision tool for this run") { opts[:decisions_enabled] = false }
        parser.on("--local-guards", "Add built-in file tools + small-model guardrails (for local models)") do
          opts[:local_guards] = true
        end
        parser.on("--no-stream", "Disable response streaming (required for local Ollama tool calls)") { opts[:stream] = false }
        parser.on("--debug", "Enable verbose JSONL logging to stderr") { opts[:debug] = true }
        parser.on("--version", "Print version and exit") { opts[:version] = true }
        parser.on("-h", "--help", "Show this help") do
          puts parser
          exit
        end
      end

      def read_stdin_objective
        return nil if $stdin.tty?

        $stdin.read.strip.then { |s| s.empty? ? nil : s }
      end
    end
  end
end
