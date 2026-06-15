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
        stat = @run.base_commit ? diff_stat : { insertions: 0, deletions: 0, files: 0 }
        aborted = !@abort_reason.nil?

        good_iters = @run.commits
        fail_iters = @run.iteration - good_iters

        puts ""
        if aborted
          puts "robot-to stopped — #{@config.model} — #{@run.elapsed_human}"
          puts "Reason: #{@abort_reason}"
        else
          puts "robot-to complete — #{@config.model} — #{@run.elapsed_human}"
          puts "Branch: #{@run.branch}"
        end

        puts ""
        puts format("%-16s %s", "Iterations:", "#{@run.iteration} total  " \
                                "(#{good_iters} good / #{fail_iters} failed)")
        puts format("%-16s %s", "Tokens:",
                    "#{comma(@run.total_tokens)}  " \
                    "(#{comma(@run.input_tokens)} in / #{comma(@run.output_tokens)} out)")
        puts format("%-16s %s", "Commits:", @run.commits.to_s)
        puts format("%-16s %s", "Changes:",
                    "+#{stat[:insertions]} / -#{stat[:deletions]} lines " \
                    "across #{stat[:files]} files")

        puts ""
        puts format("%-8s %s", "Notes:", @run.notes_path)
        puts format("%-8s %s", "Log:", @run.log_path)

        if @run.commits.positive?
          puts ""
          puts "Next steps:"
          puts "  git log --oneline #{@run.base_commit}..HEAD"
          puts "  git diff --stat #{@run.base_commit}..HEAD"
          puts "  gh pr create"
        end

        puts ""
      end

      private

      def diff_stat
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
