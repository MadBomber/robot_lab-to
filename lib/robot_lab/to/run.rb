# frozen_string_literal: true

require "json"
require "time"

module RobotLab
  module To
    # Holds mutable state for a single autonomous run.
    class Run
      attr_reader :run_id, :objective, :branch, :base_commit, :notes_path, :log_path,
                  :run_dir, :decisions_path, :started_at
      attr_accessor :iteration, :consecutive_failures, :consecutive_errors,
                    :commits, :input_tokens, :output_tokens

      def initialize(run_id:, objective:, branch:, base_commit:, notes_path:, log_path:,
                     run_dir: nil, decisions_path: nil)
        @run_id              = run_id
        @objective           = objective
        @branch              = branch
        @base_commit         = base_commit
        @notes_path          = Pathname.new(notes_path)
        @log_path            = Pathname.new(log_path)
        @run_dir             = Pathname.new(run_dir || @notes_path.parent)
        @decisions_path      = Pathname.new(decisions_path || @run_dir.join("decisions"))
        @started_at          = Time.now
        @iteration           = 0
        @consecutive_failures = 0
        @consecutive_errors  = 0
        @commits             = 0
        @input_tokens        = 0
        @output_tokens       = 0
      end

      def total_tokens     = input_tokens + output_tokens
      def elapsed_seconds  = Time.now - started_at
      def state_path       = @run_dir.join("run.json")

      def elapsed_human
        secs = elapsed_seconds.to_i
        h = secs / 3600
        m = (secs % 3600) / 60
        s = secs % 60
        if h.positive?
          "#{h}h #{m}m #{s}s"
        else
          m.positive? ? "#{m}m #{s}s" : "#{s}s"
        end
      end

      # Serializable snapshot for run.json (enables --resume across processes).
      def to_h
        {
          run_id: run_id, objective: objective, branch: branch, base_commit: base_commit,
          notes_path: notes_path.to_s, log_path: log_path.to_s, run_dir: run_dir.to_s,
          decisions_path: decisions_path.to_s, started_at: started_at.iso8601,
          iteration: iteration, consecutive_failures: consecutive_failures,
          consecutive_errors: consecutive_errors, commits: commits,
          input_tokens: input_tokens, output_tokens: output_tokens
        }
      end

      # Rebuild a Run from a run.json written by #to_h.
      def self.load(path)
        data = JSON.parse(File.read(path), symbolize_names: true)
        run  = new(run_id: data[:run_id], objective: data[:objective], branch: data[:branch],
                   base_commit: data[:base_commit], notes_path: data[:notes_path],
                   log_path: data[:log_path], run_dir: data[:run_dir],
                   decisions_path: data[:decisions_path])
        run.iteration            = data[:iteration].to_i
        run.consecutive_failures = data[:consecutive_failures].to_i
        run.consecutive_errors   = data[:consecutive_errors].to_i
        run.commits              = data[:commits].to_i
        run.input_tokens         = data[:input_tokens].to_i
        run.output_tokens        = data[:output_tokens].to_i
        run.instance_variable_set(:@started_at, Time.parse(data[:started_at])) if data[:started_at]
        run
      end

      # Derive run_id from current timestamp + random hex suffix.
      def self.generate_id
        t = Time.now
        hex = SecureRandom.hex(3)
        "#{t.strftime("%Y%m%d-%H%M%S")}-#{hex}"
      end

      # Slugify objective into a branch-name fragment (max 40 chars).
      def self.slugify(text)
        text.downcase
            .gsub(/[^a-z0-9]+/, "-")
            .gsub(/^-+|-+$/, "")
            .slice(0, 40)
            .then { |s| s.empty? ? "takeover" : s }
      end

      def self.branch_name(objective)
        slug = slugify(objective)
        ts   = Time.now.strftime("%Y%m%d-%H%M%S")
        "robot-to/#{slug}-#{ts}"
      end
    end
  end
end
