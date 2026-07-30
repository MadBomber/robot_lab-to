# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Tools
      class WriteTest < Minitest::Test
        def test_creates_file_with_content
          with_tmp_dir do |dir|
            path = dir.join("new.txt").to_s
            result = Write.new.execute(path: path, content: "hello\nworld\n")
            assert_equal "hello\nworld\n", File.read(path)
            assert_includes result, "2 lines"
          end
        end

        def test_creates_parent_directories
          with_tmp_dir do |dir|
            path = dir.join("a/b/c.txt").to_s
            Write.new.execute(path: path, content: "x")
            assert_path_exists path
          end
        end
      end
    end
  end
end
