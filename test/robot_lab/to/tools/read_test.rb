# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Tools
      class ReadTest < Minitest::Test
        def test_reads_file_contents
          with_tmp_dir do |dir|
            path = dir.join("f.txt").to_s
            File.write(path, "line1\nline2\n")
            assert_equal "line1\nline2\n", Read.new.execute(path: path)
          end
        end

        def test_returns_error_for_missing_file
          assert_includes Read.new.execute(path: "/no/such/file.xyz"), "Error: file not found"
        end

        def test_empty_file_message
          with_tmp_dir do |dir|
            path = dir.join("empty.txt").to_s
            File.write(path, "")
            assert_equal "(empty file)", Read.new.execute(path: path)
          end
        end

        def test_select_lines_honors_offset_and_limit
          lines = (1..10).map { |n| "#{n}\n" }
          assert_equal "3\n4\n", Read.new.select_lines(lines, 3, 2).join
        end

        def test_offset_limit_truncation_note
          with_tmp_dir do |dir|
            path = dir.join("big.txt").to_s
            File.write(path, (1..10).map { |n| "#{n}\n" }.join)
            out = Read.new.execute(path: path, offset: 1, limit: 2)
            assert_includes out, "truncated"
          end
        end
      end
    end
  end
end
