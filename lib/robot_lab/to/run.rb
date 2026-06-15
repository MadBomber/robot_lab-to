# frozen_string_literal: true

module RobotLab
  module To
    # Holds mutable state for a single autonomous run.
    class Run
      attr_reader :run_id, :objective, :branch, :base_commit, :notes_path, :log_path, :started_at
      attr_accessor :iteration, :consecutive_failures, :consecutive_errors,
                    :commits, :input_tokens, :output_tokens

      def initialize(run_id:, objective:, branch:, base_commit:, notes_path:, log_path:)
        @run_id              = run_id
        @objective           = objective
        @branch              = branch
        @base_commit         = base_commit
        @notes_path          = Pathname.new(notes_path)
        @log_path            = Pathname.new(log_path)
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
