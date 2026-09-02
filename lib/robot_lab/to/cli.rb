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
        ["--eval NAME", String, "Eval strategy: code | null (default: code when --verify-command set)", :eval],
        ["--measure CMD", String,
         "Command printing a numeric score; higher is better (Evals::Code)", :eval_measure],
        ["--target FLOAT", Float, "Stop once the measured score reaches TARGET", :eval_target],
        ["--spec PATH", String, "Spec/outline artifact the eval measures against (Evals::Prose)", :eval_spec],
        ["--floor CMD", String,
         "Mechanizable floor-check command for prose (links, coverage, AI-tells)", :eval_floor],
        ["--judge-model MODEL", String,
         "Model for the pairwise prose judge (default: --model)", :eval_judge_model],
        ["--stop-on-plateau N", Integer,
         "Stop after N iterations with no committed improvement", :stop_on_plateau],
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

      # Boolean flags with a fixed value when passed (no argument). Flags
      # needing bespoke behavior (protect-path, require-improvement, help)
      # stay in #add_flag_options.
      BOOLEAN_FLAGS = [
        ["--no-decisions", "Disable the request_decision tool for this run", :decisions_enabled, false],
        ["--local-guards", "Add built-in file tools + small-model guardrails (for local models)", :local_guards, true],
        ["--no-stream", "Disable response streaming (required for local Ollama tool calls)", :stream, false],
        ["--debug", "Enable verbose JSONL logging to stderr", :debug, true],
        ["--version", "Print version and exit", :version, true]
      ].freeze

      def self.run(argv = ARGV)
        new.run(argv)
      end

      def run(argv)
        return run_decisions(argv[1..] || []) if argv.first == "decisions"

        opts, parser, args = parse_options(argv)

        return puts("robot-to #{VERSION}") if opts[:version]
        return RobotLab::To.resume(opts[:resume], **opts.except(:version, :resume)) if opts[:resume]

        objective = args.first || read_stdin_objective
        abort_missing_objective!(parser) if objective.nil? || objective.strip.empty?

        RobotLab::To.run(objective.strip, **opts.except(:version, :resume))
      end

      private

      def parse_options(argv)
        opts   = {}
        parser = build_parser(opts)
        args   = parser.parse!(argv.dup)
        [opts, parser, args]
      end

      def abort_missing_objective!(parser)
        # $stderr.puts, not warn: warn is silenced when $VERBOSE is nil.
        $stderr.puts "Error: objective required (pass as argument or via stdin)"
        $stderr.puts parser
        exit 1
      end

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

        if pending.empty? && resolved.empty?
          puts "Run #{run_id}\n\nNo open decisions."
          return
        end

        puts "Run #{run_id}\n\n"
        list_group("Pending (awaiting your answer)", pending)
        list_group("Resolved (not yet consumed)", resolved)
        puts <<~MSG
          Resolve a pending decision by editing its file: set `status: resolved`
          and fill `resolution:`, then run `robot-to --resume #{run_id}`.
        MSG
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

      # :reek:FeatureEnvy -- configuring the OptionParser instance being built.
      def build_parser(opts)
        OptionParser.new do |p|
          p.banner = "Usage: robot-to [objective] [options]\n       " \
                     "robot-to --resume RUN_ID [options]\n       " \
                     "robot-to decisions [RUN_ID]"
          p.separator ""
          p.separator "Runs a robot_lab Robot in an autonomous loop toward the given objective."
          p.separator ""
          p.separator "Options:"

          add_value_options(p, opts)
          add_flag_options(p, opts)
        end
      end

      # :reek:NestedIterators -- one .on registration per option, each with its
      # own value-assignment callback; that's the OptionParser API shape.
      def add_value_options(parser, opts)
        VALUE_OPTIONS.each do |flag, type, desc, key|
          parser.on(flag, type, desc) { |v| opts[key] = v }
        end
      end

      # :reek:FeatureEnvy -- registering flags on the OptionParser being built.
      # Boolean and terminal flags (each has bespoke behavior).
      def add_flag_options(parser, opts)
        add_require_improvement_option(parser, opts)
        add_protect_path_option(parser, opts)
        BOOLEAN_FLAGS.each { |flag, desc, key, value| parser.on(flag, desc) { opts[key] = value } }
        add_help_option(parser)
      end

      def add_require_improvement_option(parser, opts)
        parser.on("--[no-]require-improvement",
                  "Roll back gate-passing iterations that don't improve (default: on)") do |v|
          opts[:require_improvement] = v
        end
      end

      def add_protect_path_option(parser, opts)
        parser.on("--protect-path GLOB", "Lock a grader file from robot edits (repeatable)") do |v|
          (opts[:protect_paths] ||= []) << v
        end
      end

      def add_help_option(parser)
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
