# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class CommitManagerTest < Minitest::Test
      # These tests require a real git repo in a temp dir.
      def setup
        @tmpdir = Dir.mktmpdir
        system("git", "-C", @tmpdir, "init", "-q")
        system("git", "-C", @tmpdir, "config", "user.email", "test@test.com")
        system("git", "-C", @tmpdir, "config", "user.name", "Test")
        @cm = CommitManager.new(work_dir: @tmpdir)
      end

      def teardown
        FileUtils.rm_rf(@tmpdir)
      end

      def test_head_sha_after_initial_commit
        File.write(File.join(@tmpdir, "README.md"), "hello")
        system("git", "-C", @tmpdir, "add", "-A", out: File::NULL, err: File::NULL)
        system("git", "-C", @tmpdir, "commit", "-m", "init", out: File::NULL, err: File::NULL)
        sha = @cm.head_sha
        assert_match(/\A[0-9a-f]{40}\z/, sha)
      end

      def test_changed_vs_worktree_lists_uncommitted_edits
        commit_file("doc.md", "v1")
        File.write(File.join(@tmpdir, "doc.md"), "v2 draft")
        assert_equal ["doc.md"], @cm.changed_vs_worktree("HEAD")
      end

      def test_show_returns_committed_contents
        commit_file("doc.md", "committed body")
        File.write(File.join(@tmpdir, "doc.md"), "working changes")
        assert_equal "committed body", @cm.show("HEAD", "doc.md").chomp
      end

      def test_show_returns_empty_for_missing_path
        commit_file("doc.md", "x")
        assert_equal "", @cm.show("HEAD", "nope.md")
      end

      def commit_file(name, body)
        File.write(File.join(@tmpdir, name), body)
        system("git", "-C", @tmpdir, "add", "-A", out: File::NULL, err: File::NULL)
        system("git", "-C", @tmpdir, "commit", "-m", "c", out: File::NULL, err: File::NULL)
      end

      def test_staged_false_when_nothing_staged
        File.write(File.join(@tmpdir, "README.md"), "hello")
        # file is untracked, not staged
        refute @cm.staged?
      end

      def test_tracked_files_lists_committed_paths
        File.write(File.join(@tmpdir, "a.rb"), "1")
        FileUtils.mkdir_p(File.join(@tmpdir, "test"))
        File.write(File.join(@tmpdir, "test", "a_test.rb"), "2")
        system("git", "-C", @tmpdir, "add", "-A", out: File::NULL, err: File::NULL)
        system("git", "-C", @tmpdir, "commit", "-m", "init", out: File::NULL, err: File::NULL)
        assert_equal ["a.rb", "test/a_test.rb"], @cm.tracked_files.sort
      end

      def test_tracked_files_empty_before_any_commit
        assert_empty @cm.tracked_files
      end

      def test_staged_true_after_add_all
        File.write(File.join(@tmpdir, "README.md"), "hello")
        @cm.add_all
        assert @cm.staged?
      end

      def test_add_to_local_exclude
        @cm.add_to_local_exclude(".robot_lab_to")
        exclude = File.read(File.join(@tmpdir, ".git", "info", "exclude"))
        assert_includes exclude, ".robot_lab_to"
      end

      def test_add_to_local_exclude_idempotent
        @cm.add_to_local_exclude(".robot_lab_to")
        @cm.add_to_local_exclude(".robot_lab_to")
        exclude = File.read(File.join(@tmpdir, ".git", "info", "exclude"))
        assert_equal 1, exclude.scan(".robot_lab_to").length
      end

      def test_reset_hard_removes_staged_changes
        File.write(File.join(@tmpdir, "init.txt"), "init")
        system("git", "-C", @tmpdir, "add", "-A", out: File::NULL, err: File::NULL)
        system("git", "-C", @tmpdir, "commit", "-m", "init", out: File::NULL, err: File::NULL)

        File.write(File.join(@tmpdir, "new.txt"), "change")
        @cm.add_all
        assert @cm.staged?
        @cm.reset_hard
        refute @cm.staged?
      end

      def test_current_branch_returns_branch_name
        File.write(File.join(@tmpdir, "README.md"), "hello")
        system("git", "-C", @tmpdir, "add", "-A", out: File::NULL, err: File::NULL)
        system("git", "-C", @tmpdir, "commit", "-m", "init", out: File::NULL, err: File::NULL)
        branch = @cm.current_branch
        refute branch.nil?
        refute branch.empty?
      end

      def test_commit_raises_commit_failed_error_on_failure
        # Commit with nothing staged should fail
        err = assert_raises(CommitFailedError) { @cm.commit("nothing staged") }
        refute_nil err.output
      end

      def test_changed_files_since_lists_new_files
        File.write(File.join(@tmpdir, "a.rb"), "init")
        system("git", "-C", @tmpdir, "add", "-A", out: File::NULL, err: File::NULL)
        system("git", "-C", @tmpdir, "commit", "-m", "init", out: File::NULL, err: File::NULL)
        base = @cm.head_sha

        File.write(File.join(@tmpdir, "b.rb"), "new")
        system("git", "-C", @tmpdir, "add", "-A", out: File::NULL, err: File::NULL)
        system("git", "-C", @tmpdir, "commit", "-m", "add b", out: File::NULL, err: File::NULL)

        files = @cm.changed_files_since(base)
        assert_includes files, "b.rb"
        refute_includes files, "a.rb"
      end

      def test_changed_files_since_empty_when_no_changes
        File.write(File.join(@tmpdir, "a.rb"), "init")
        system("git", "-C", @tmpdir, "add", "-A", out: File::NULL, err: File::NULL)
        system("git", "-C", @tmpdir, "commit", "-m", "init", out: File::NULL, err: File::NULL)
        base = @cm.head_sha
        assert_empty @cm.changed_files_since(base)
      end
    end
  end
end
