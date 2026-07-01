# frozen_string_literal: true

require "open3"

module RobotLab
  module To
    # All git operations needed by the orchestrator.
    #
    # All subprocess calls use explicit argv arrays (no shell interpolation).
    # GIT_TERMINAL_PROMPT=0 prevents credential prompts from hanging the loop.
    class CommitManager
      GIT_ENV = { "GIT_TERMINAL_PROMPT" => "0" }.freeze

      def initialize(work_dir: Dir.pwd)
        @work_dir = work_dir
      end

      def current_branch
        git("rev-parse", "--abbrev-ref", "HEAD").chomp
      end

      def head_sha
        git("rev-parse", "HEAD").chomp
      end

      def create_branch(name)
        git("checkout", "-b", name)
      end

      # Switch to an existing branch (used when resuming a prior run).
      def checkout_branch(name)
        git("checkout", name)
      end

      def staged?
        _out, _err, status = Open3.capture3(GIT_ENV, "git", "diff", "--cached", "--quiet",
                                            chdir: @work_dir)
        !status.success? # exit 1 = changes are staged
      end

      def add_all
        git("add", "-A")
      end

      def commit(message)
        out, err, status = Open3.capture3(
          GIT_ENV, "git", "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false",
          "commit", "-m", message,
          chdir: @work_dir
        )
        return if status.success?

        raise CommitFailedError.new("git commit failed", output: (out + err).strip)
      end

      def head_exists?
        _out, _err, status = Open3.capture3(GIT_ENV, "git", "rev-parse", "--verify", "HEAD",
                                            chdir: @work_dir)
        status.success?
      end

      def reset_hard
        return unless head_exists?

        git("reset", "--hard", "HEAD")
        git("clean", "-fd")
      end

      def diff_stat(base_sha)
        out, _err, _status = Open3.capture3(GIT_ENV, "git", "diff", "--stat",
                                            "#{base_sha}..HEAD", chdir: @work_dir)
        parse_diff_stat(out)
      end

      def add_to_local_exclude(entry)
        exclude = Pathname.new(@work_dir).join(".git", "info", "exclude")
        exclude.parent.mkpath
        content = exclude.exist? ? exclude.read : ""
        return if content.include?(entry)

        File.open(exclude, "a") { |f| f.puts(entry) }
      end

      def changed_files_since(base_sha)
        out, _err, _status = Open3.capture3(GIT_ENV, "git", "diff", "--name-only",
                                            "#{base_sha}..HEAD", chdir: @work_dir)
        out.lines.map(&:chomp).reject(&:empty?)
      end

      # All tracked files — the project's committed layout. Excludes the run dir
      # (it's in .git/info/exclude), so it's a clean workspace digest.
      def tracked_files
        out, _err, status = Open3.capture3(GIT_ENV, "git", "ls-files", chdir: @work_dir)
        return [] unless status.success?

        out.lines.map(&:chomp).reject(&:empty?)
      end

      private

      def git(*args)
        out, err, status = Open3.capture3(GIT_ENV, "git", *args, chdir: @work_dir)
        raise PermanentError, "git #{args.first} failed: #{err.strip}" unless status.success?

        out
      end

      def parse_diff_stat(text)
        insertions = text.scan(/(\d+) insertion/).flatten.map(&:to_i).sum
        deletions  = text.scan(/(\d+) deletion/).flatten.map(&:to_i).sum
        files      = text.scan(/(\d+) file/).flatten.map(&:to_i).first || 0
        { insertions: insertions, deletions: deletions, files: files }
      end
    end
  end
end
