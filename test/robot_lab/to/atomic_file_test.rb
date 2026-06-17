# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class AtomicFileTest < Minitest::Test
      def test_write_creates_file_with_content
        with_tmp_dir do |dir|
          path = dir.join("state.txt")
          AtomicFile.write(path, "hello")
          assert_equal "hello", path.read
        end
      end

      def test_write_replaces_existing_content
        with_tmp_dir do |dir|
          path = dir.join("state.txt")
          AtomicFile.write(path, "first")
          AtomicFile.write(path, "second")
          assert_equal "second", path.read
        end
      end

      def test_write_creates_missing_parent_dirs
        with_tmp_dir do |dir|
          path = dir.join("nested", "deep", "state.txt")
          AtomicFile.write(path, "x")
          assert_equal "x", path.read
        end
      end

      def test_write_accepts_string_path
        with_tmp_dir do |dir|
          path = dir.join("state.txt")
          AtomicFile.write(path.to_s, "stringy")
          assert_equal "stringy", path.read
        end
      end

      def test_append_concatenates_in_order
        with_tmp_dir do |dir|
          path = dir.join("notes.md")
          AtomicFile.write(path, "a")
          AtomicFile.append(path, "b")
          AtomicFile.append(path, "c")
          assert_equal "abc", path.read
        end
      end

      def test_append_creates_file_when_missing
        with_tmp_dir do |dir|
          path = dir.join("notes.md")
          AtomicFile.append(path, "fresh")
          assert_equal "fresh", path.read
        end
      end

      def test_no_temp_files_left_behind
        with_tmp_dir do |dir|
          path = dir.join("notes.md")
          AtomicFile.write(path, "x")
          AtomicFile.append(path, "y")
          leftovers = dir.children.map { |c| c.basename.to_s }.select { |n| n.end_with?(".tmp") }
          assert_empty leftovers
        end
      end
    end
  end
end
