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

      def test_staged_false_when_nothing_staged
        File.write(File.join(@tmpdir, "README.md"), "hello")
        # file is untracked, not staged
        refute @cm.staged?
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
    end
  end
end
