# frozen_string_literal: true

module RobotLab
  module To
    # Prints the post-run summary to stdout.
    class ExitSummary
      def initialize(run, config, abort_reason: nil)
        @run          = run
        @config       = config
        @abort_reason = abort_reason
      end

      def print
        puts ""
        @abort_reason ? print_aborted_header : print_completed_header
        print_counters
        print_paths
        print_next_steps
        puts ""
      end

      private

      def print_aborted_header
        puts "robot-to stopped — #{@config.model} — #{@run.elapsed_human}"
        puts "Reason: #{@abort_reason}"
      end

      def print_completed_header
        puts "robot-to complete — #{@config.model} — #{@run.elapsed_human}"
        puts "Branch: #{@run.branch}"
      end

      def print_counters
        good_iters = @run.commits
        fail_iters = @run.iteration - good_iters
        stat       = diff_stat

        puts ""
        puts "Iterations:      #{@run.iteration} total  (#{good_iters} good / #{fail_iters} failed)"
        puts "Tokens:          #{comma(@run.total_tokens)}  (#{comma(@run.input_tokens)} in / #{comma(@run.output_tokens)} out)"
        puts format("%-16s %s", "Commits:", @run.commits.to_s)
        puts "Changes:         +#{stat[:insertions]} / -#{stat[:deletions]} lines across #{stat[:files]} files"
      end

      def print_paths
        puts ""
        puts format("%-8s %s", "Notes:", @run.notes_path)
        puts format("%-8s %s", "Log:", @run.log_path)
      end

      def print_next_steps
        return unless @run.commits.positive?

        puts ""
        puts "Next steps:"
        puts "  git log --oneline #{@run.base_commit}..HEAD"
        puts "  git diff --stat #{@run.base_commit}..HEAD"
        puts "  gh pr create"
      end

      def diff_stat
        return { insertions: 0, deletions: 0, files: 0 } unless @run.base_commit

        git = CommitManager.new
        git.diff_stat(@run.base_commit)
      rescue StandardError
        { insertions: 0, deletions: 0, files: 0 }
      end

      def comma(n)
        n.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
      end
    end
  end
end
